import SwiftUI
import ARKit
import AVFoundation
import Combine
import CoreVideo

// MARK: - Models

struct IntrinsicsSample: Codable {
    let timestamp: Double

    let cameraWidth: Int
    let cameraHeight: Int

    let bufferWidth: Int
    let bufferHeight: Int

    let fx: Double
    let fy: Double
    let cx: Double
    let cy: Double
}

struct IntrinsicsStatistics: Codable {
    let sampleCount: Int

    let width: Int
    let height: Int

    let fxMean: Double
    let fyMean: Double
    let cxMean: Double
    let cyMean: Double

    let fxStd: Double
    let fyStd: Double
    let cxStd: Double
    let cyStd: Double

    let intrinsicMatrixMean: [[Double]]
}

struct VideoFormatInfo: Codable {
    let width: Int
    let height: Int
    let framesPerSecond: Int
    let isRecommendedForHighResolutionFrameCapturing: Bool

    let defaultPhotoMaxWidth: Int
    let defaultPhotoMaxHeight: Int
}

struct IntrinsicsExport: Codable {
    let deviceType: String
    let systemName: String
    let systemVersion: String

    let warmupFrames: Int
    let targetStreamSamples: Int
    let targetHighResolutionSamples: Int

    let selectedVideoFormat: VideoFormatInfo

    let requestedHighResolutionWidth: Int?
    let requestedHighResolutionHeight: Int?

    // Mantidos com os nomes antigos para compatibilidade.
    let statistics: IntrinsicsStatistics
    let samples: [IntrinsicsSample]

    // Dados adicionais em alta resolução.
    let highResolutionStatistics: IntrinsicsStatistics?
    let highResolutionSamples: [IntrinsicsSample]
}

// MARK: - Collector

final class IntrinsicsCollector:
    NSObject,
    ObservableObject,
    ARSessionDelegate
{
    @Published var status = "Pronto para iniciar."
    @Published var resultText = ""
    @Published var exportURL: URL?
    @Published var isCollecting = false

    private let session = ARSession()

    private var samples: [IntrinsicsSample] = []
    private var highResolutionSamples: [IntrinsicsSample] = []

    private var selectedFormat: ARConfiguration.VideoFormat?

    private var warmupFramesRemaining = 0
    private var isCapturingHighResolution = false
    private var highResolutionAttempts = 0

    private let warmupFrames = 30
    private let targetSamples = 120
    private let targetHighResolutionSamples = 5

    private let maximumHighResolutionAttempts = 15

    override init() {
        super.init()
        session.delegate = self
    }

    // MARK: - Start / Stop

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else {
            status =
                "ARWorldTrackingConfiguration não é suportado neste dispositivo."
            return
        }

        samples.removeAll()
        highResolutionSamples.removeAll()

        resultText = ""
        exportURL = nil

        warmupFramesRemaining = warmupFrames
        highResolutionAttempts = 0
        isCapturingHighResolution = false
        isCollecting = true

        let configuration = ARWorldTrackingConfiguration()

        configuration.planeDetection = []
        configuration.isLightEstimationEnabled = false

        /*
         Para a maior fidelidade possível, usamos um formato que
         o próprio ARKit recomenda para captura still em alta resolução.
         */
        if let recommendedFormat =
            ARWorldTrackingConfiguration
                .recommendedVideoFormatForHighResolutionFrameCapturing
        {
            configuration.videoFormat = recommendedFormat
            selectedFormat = recommendedFormat

        } else if let firstFormat =
                    ARWorldTrackingConfiguration
                        .supportedVideoFormats
                        .first
        {
            configuration.videoFormat = firstFormat
            selectedFormat = firstFormat

        } else {
            status = "Nenhum formato de vídeo ARKit foi encontrado."
            isCollecting = false
            return
        }

        guard let format = selectedFormat else {
            isCollecting = false
            return
        }

        let photoDimensions =
            format.defaultPhotoSettings.maxPhotoDimensions

        status = """
        Iniciando sessão.

        Stream ARKit:
        \(Int(format.imageResolution.width)) × \(Int(format.imageResolution.height))
        \(format.framesPerSecond) FPS

        Default high-resolution request:
        \(photoDimensions.width) × \(photoDimensions.height)

        Warm-up:
        \(warmupFrames) frames
        """

        session.run(
            configuration,
            options: [
                .resetTracking,
                .removeExistingAnchors
            ]
        )
    }

    func stop() {
        isCollecting = false
        isCapturingHighResolution = false

        session.pause()

        status = "Sessão interrompida."
    }

    // MARK: - Stream frames

    func session(
        _ session: ARSession,
        didUpdate frame: ARFrame
    ) {
        guard isCollecting else {
            return
        }

        /*
         Durante as capturas still em alta resolução,
         continuamos com a sessão ativa, mas não adicionamos
         mais frames normais ao conjunto.
         */
        guard !isCapturingHighResolution else {
            return
        }

        if warmupFramesRemaining > 0 {
            warmupFramesRemaining -= 1

            let remaining = warmupFramesRemaining

            DispatchQueue.main.async {
                self.status = """
                Estabilizando câmera...

                Warm-up:
                \(self.warmupFrames - remaining) / \(self.warmupFrames)
                """
            }

            return
        }

        let sample = makeSample(from: frame)

        samples.append(sample)

        let currentCount = samples.count

        DispatchQueue.main.async {
            self.status = """
            Coletando intrínsecos do stream...

            \(currentCount) / \(self.targetSamples)

            Resolução:
            \(sample.cameraWidth) × \(sample.cameraHeight)
            """
        }

        if currentCount >= targetSamples {
            isCapturingHighResolution = true

            DispatchQueue.main.async {
                self.status = """
                Stream concluído.

                Iniciando capturas still em alta resolução...
                """
            }

            captureNextHighResolutionFrame()
        }
    }

    // MARK: - High-resolution capture

    private func captureNextHighResolutionFrame() {
        guard isCollecting else {
            return
        }

        if highResolutionSamples.count >=
            targetHighResolutionSamples
        {
            finishCollection()
            return
        }

        if highResolutionAttempts >=
            maximumHighResolutionAttempts
        {
            finishCollection()
            return
        }

        guard let format = selectedFormat else {
            finishCollection()
            return
        }

        highResolutionAttempts += 1

        let settings =
            format.defaultPhotoSettings

        /*
         Tentamos utilizar exatamente a mesma resolução
         das imagens empregadas na calibração de Zhang:

         iPhone:
         HEIC em retrato = 4284 × 5712
         orientação nativa = 5712 × 4284

         iPad:
         HEIC em retrato = 2448 × 3264
         orientação nativa = 3264 × 2448

         maxPhotoDimensions deve ser uma dimensão realmente
         suportada pelo formato ativo.
         */
        if let captureDevice =
            ARWorldTrackingConfiguration
                .configurableCaptureDeviceForPrimaryCamera
        {
            let supportedDimensions =
                captureDevice
                    .activeFormat
                    .supportedMaxPhotoDimensions

            if let desired =
                desiredHighResolutionDimensions(),
               let exact =
                supportedDimensions.first(
                    where: {
                        $0.width == desired.width &&
                        $0.height == desired.height
                    }
                )
            {
                settings.maxPhotoDimensions = exact

            } else if let largest =
                        supportedDimensions.max(
                            by: {
                                pixelCount($0) <
                                pixelCount($1)
                            }
                        )
            {
                /*
                 Caso a resolução das fotos da calibração
                 não seja suportada pelo pipeline ARKit,
                 solicitamos a maior disponível.
                 */
                settings.maxPhotoDimensions = largest
            }
        }

        let requested =
            settings.maxPhotoDimensions

        let nextIndex =
            highResolutionSamples.count + 1

        DispatchQueue.main.async {
            self.status = """
            Capturando frame high-resolution...

            \(nextIndex) / \(self.targetHighResolutionSamples)

            Resolução solicitada:
            \(requested.width) × \(requested.height)
            """
        }

        session.captureHighResolutionFrame(
            using: settings
        ) { [weak self] frame, error in

            guard let self else {
                return
            }

            if let frame {
                let sample =
                    self.makeSample(
                        from: frame
                    )

                self.highResolutionSamples
                    .append(sample)

                print(
                    """
                    High-resolution frame \(self.highResolutionSamples.count):
                    camera = \(sample.cameraWidth) × \(sample.cameraHeight)
                    buffer = \(sample.bufferWidth) × \(sample.bufferHeight)
                    fx = \(sample.fx)
                    fy = \(sample.fy)
                    cx = \(sample.cx)
                    cy = \(sample.cy)
                    """
                )
            }

            if let error {
                print(
                    "Erro na captura high-resolution: \(error)"
                )
            }

            /*
             Evita solicitar outra captura enquanto o pipeline
             ainda está encerrando a anterior.
             */
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.25
            ) {
                self.captureNextHighResolutionFrame()
            }
        }
    }

    // MARK: - Target still resolution

    private func desiredHighResolutionDimensions()
        -> CMVideoDimensions?
    {
        switch UIDevice.current.userInterfaceIdiom {

        case .phone:
            /*
             iPhone 15:
             fotos de calibração em retrato 4284 × 5712.
             O ARKit trabalha na orientação nativa.
             */
            return CMVideoDimensions(
                width: 5712,
                height: 4284
            )

        case .pad:
            /*
             iPad 9:
             fotos de calibração em retrato 2448 × 3264.
             */
            return CMVideoDimensions(
                width: 3264,
                height: 2448
            )

        default:
            return nil
        }
    }

    private func pixelCount(
        _ dimensions: CMVideoDimensions
    ) -> Int64 {
        Int64(dimensions.width) *
        Int64(dimensions.height)
    }

    // MARK: - Frame -> sample

    private func makeSample(
        from frame: ARFrame
    ) -> IntrinsicsSample {

        /*
         ARCamera.intrinsics:

             [ fx   0   cx ]
         K = [  0  fy   cy ]
             [  0   0    1 ]

         simd_float3x3 é armazenada por colunas.
         */

        let K = frame.camera.intrinsics

        let fx =
            Double(K.columns.0.x)

        let fy =
            Double(K.columns.1.y)

        let cx =
            Double(K.columns.2.x)

        let cy =
            Double(K.columns.2.y)

        let resolution =
            frame.camera.imageResolution

        let pixelBuffer =
            frame.capturedImage

        return IntrinsicsSample(
            timestamp:
                frame.timestamp,

            cameraWidth:
                Int(resolution.width),

            cameraHeight:
                Int(resolution.height),

            bufferWidth:
                CVPixelBufferGetWidth(
                    pixelBuffer
                ),

            bufferHeight:
                CVPixelBufferGetHeight(
                    pixelBuffer
                ),

            fx:
                fx,

            fy:
                fy,

            cx:
                cx,

            cy:
                cy
        )
    }

    // MARK: - Statistics

    private func mean(
        _ values: [Double]
    ) -> Double {
        values.reduce(0.0, +)
        / Double(values.count)
    }

    private func standardDeviation(
        _ values: [Double],
        mean: Double
    ) -> Double {
        let variance =
            values
                .map {
                    let d = $0 - mean
                    return d * d
                }
                .reduce(0.0, +)
            / Double(values.count)

        return sqrt(variance)
    }

    private func makeStatistics(
        from source: [IntrinsicsSample]
    ) -> IntrinsicsStatistics? {

        guard !source.isEmpty else {
            return nil
        }

        let fxValues = source.map { $0.fx }
        let fyValues = source.map { $0.fy }
        let cxValues = source.map { $0.cx }
        let cyValues = source.map { $0.cy }

        let fxMean = mean(fxValues)
        let fyMean = mean(fyValues)
        let cxMean = mean(cxValues)
        let cyMean = mean(cyValues)

        return IntrinsicsStatistics(
            sampleCount:
                source.count,

            width:
                source[0].cameraWidth,

            height:
                source[0].cameraHeight,

            fxMean:
                fxMean,

            fyMean:
                fyMean,

            cxMean:
                cxMean,

            cyMean:
                cyMean,

            fxStd:
                standardDeviation(
                    fxValues,
                    mean: fxMean
                ),

            fyStd:
                standardDeviation(
                    fyValues,
                    mean: fyMean
                ),

            cxStd:
                standardDeviation(
                    cxValues,
                    mean: cxMean
                ),

            cyStd:
                standardDeviation(
                    cyValues,
                    mean: cyMean
                ),

            intrinsicMatrixMean: [
                [
                    fxMean,
                    0.0,
                    cxMean
                ],
                [
                    0.0,
                    fyMean,
                    cyMean
                ],
                [
                    0.0,
                    0.0,
                    1.0
                ]
            ]
        )
    }

    // MARK: - Finalization

    private func finishCollection() {
        guard
            let streamStatistics =
                makeStatistics(
                    from: samples
                ),
            let format =
                selectedFormat
        else {
            return
        }

        isCollecting = false
        isCapturingHighResolution = false

        session.pause()

        let highResolutionStatistics =
            makeStatistics(
                from:
                    highResolutionSamples
            )

        let defaultPhotoDimensions =
            format
                .defaultPhotoSettings
                .maxPhotoDimensions

        let videoFormat =
            VideoFormatInfo(
                width:
                    Int(
                        format
                            .imageResolution
                            .width
                    ),

                height:
                    Int(
                        format
                            .imageResolution
                            .height
                    ),

                framesPerSecond:
                    format
                        .framesPerSecond,

                isRecommendedForHighResolutionFrameCapturing:
                    format
                        .isRecommendedForHighResolutionFrameCapturing,

                defaultPhotoMaxWidth:
                    Int(
                        defaultPhotoDimensions.width
                    ),

                defaultPhotoMaxHeight:
                    Int(
                        defaultPhotoDimensions.height
                    )
            )

        let deviceType: String

        switch UIDevice
            .current
            .userInterfaceIdiom
        {
        case .phone:
            deviceType = "iPhone"

        case .pad:
            deviceType = "iPad"

        default:
            deviceType =
                UIDevice
                    .current
                    .model
        }

        let desired =
            desiredHighResolutionDimensions()

        let output =
            IntrinsicsExport(
                deviceType:
                    deviceType,

                systemName:
                    UIDevice
                        .current
                        .systemName,

                systemVersion:
                    UIDevice
                        .current
                        .systemVersion,

                warmupFrames:
                    warmupFrames,

                targetStreamSamples:
                    targetSamples,

                targetHighResolutionSamples:
                    targetHighResolutionSamples,

                selectedVideoFormat:
                    videoFormat,

                requestedHighResolutionWidth:
                    desired.map {
                        Int($0.width)
                    },

                requestedHighResolutionHeight:
                    desired.map {
                        Int($0.height)
                    },

                statistics:
                    streamStatistics,

                samples:
                    samples,

                highResolutionStatistics:
                    highResolutionStatistics,

                highResolutionSamples:
                    highResolutionSamples
            )

        do {
            let encoder =
                JSONEncoder()

            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys
            ]

            let jsonData =
                try encoder.encode(
                    output
                )

            let filename: String

            if deviceType == "iPhone" {
                filename =
                    "arkit_intrinsics_iphone15.json"

            } else if deviceType == "iPad" {
                filename =
                    "arkit_intrinsics_ipad9.json"

            } else {
                filename =
                    "arkit_intrinsics.json"
            }

            let fileURL =
                FileManager
                    .default
                    .urls(
                        for:
                            .documentDirectory,
                        in:
                            .userDomainMask
                    )[0]
                    .appendingPathComponent(
                        filename
                    )

            try jsonData.write(
                to: fileURL,
                options: .atomic
            )

            var text = """
            Coleta concluída.

            STREAM ARKit
            Amostras:
            \(streamStatistics.sampleCount)

            Resolução:
            \(streamStatistics.width) × \(streamStatistics.height)

            K médio:

            [ \(streamStatistics.fxMean)   0   \(streamStatistics.cxMean) ]
            [ 0   \(streamStatistics.fyMean)   \(streamStatistics.cyMean) ]
            [ 0   0   1 ]

            Desvio-padrão:

            fx = \(streamStatistics.fxStd)
            fy = \(streamStatistics.fyStd)
            cx = \(streamStatistics.cxStd)
            cy = \(streamStatistics.cyStd)
            """

            if let high =
                highResolutionStatistics
            {
                text +=
                """


                HIGH-RESOLUTION
                Amostras:
                \(high.sampleCount)

                Resolução:
                \(high.width) × \(high.height)

                K médio:

                [ \(high.fxMean)   0   \(high.cxMean) ]
                [ 0   \(high.fyMean)   \(high.cyMean) ]
                [ 0   0   1 ]

                Desvio-padrão:

                fx = \(high.fxStd)
                fy = \(high.fyStd)
                cx = \(high.cxStd)
                cy = \(high.cyStd)
                """
            } else {
                text +=
                    """


                    HIGH-RESOLUTION
                    Nenhuma captura high-resolution foi concluída.
                    """
            }

            print(text)

            DispatchQueue.main.async {
                self.resultText = text
                self.exportURL = fileURL
                self.status = "Coleta concluída."
            }

        } catch {
            DispatchQueue.main.async {
                self.status =
                    """
                    Erro ao salvar JSON:

                    \(error.localizedDescription)
                    """
            }
        }
    }
}

// MARK: - UI

struct ContentView: View {

    @StateObject
    private var collector =
        IntrinsicsCollector()

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(
                    alignment: .leading,
                    spacing: 20
                ) {

                    Text(
                        "ARKit Camera Intrinsics"
                    )
                    .font(.title)
                    .fontWeight(.semibold)

                    Text(
                        collector.status
                    )

                    Button {
                        collector.start()

                    } label: {

                        Text(
                            collector.isCollecting
                            ? "Coletando..."
                            : "Coletar parâmetros"
                        )
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .disabled(
                        collector.isCollecting
                    )

                    if collector.isCollecting {

                        Button(
                            "Interromper"
                        ) {
                            collector.stop()
                        }
                        .buttonStyle(
                            .bordered
                        )
                    }

                    if !collector
                        .resultText
                        .isEmpty
                    {
                        Divider()

                        Text(
                            collector.resultText
                        )
                        .font(
                            .system(
                                .body,
                                design:
                                    .monospaced
                            )
                        )
                        .textSelection(
                            .enabled
                        )
                    }

                    if let url =
                        collector.exportURL
                    {
                        ShareLink(
                            item: url
                        ) {
                            Label(
                                "Compartilhar JSON",
                                systemImage:
                                    "square.and.arrow.up"
                            )
                        }
                        .buttonStyle(
                            .bordered
                        )
                    }
                }
                .padding()
            }
            .navigationTitle(
                "Intrínsecos"
            )
        }
        .onDisappear {
            collector.stop()
        }
    }
}
