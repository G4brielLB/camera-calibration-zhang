# Calibração de câmeras pelo método de Zhang

Projeto da Atividade Prática 01 da disciplina de Visão Computacional da Universidade Federal do Piauí. O método de Zhang foi implementado para calibrar as câmeras principais de um iPhone 15 e de um iPad de 9ª geração. Os parâmetros obtidos são comparados com duas configurações da rotina `cv2.calibrateCamera` e com matrizes fornecidas pelo ARKit.

## Imagens e padrão de calibração

| Dispositivo | Fotografias HEIC | Resolução |
| --- | ---: | ---: |
| iPhone 15 | 41 | 4284 × 5712 pixels |
| iPad de 9ª geração | 36 | 2448 × 3264 pixels |

As fotografias originais não são incluídas no Git. Para executar as calibrações, coloque os arquivos HEIC em `images/iphone15/` e `images/ipad9/`, respectivamente.

O arquivo `images/pattern.png` contém o tabuleiro obtido no [repositório oficial do OpenCV](https://github.com/opencv/opencv/blob/5.x/doc/pattern.png). O padrão possui 9 × 6 cantos internos, totalizando 54 pontos. Ele foi impresso em folha A4 com escala de 100%, sem ajuste automático à página, e o lado de cada quadrado foi medido em 25 mm. Há mais informações em [`images/README.md`](images/README.md).

## Notebooks

Execute os notebooks na ordem abaixo, a partir da pasta do projeto:

1. [`notebooks/01_zhang_calibration.ipynb`](notebooks/01_zhang_calibration.ipynb) implementa as etapas de Zhang e salva os parâmetros e os erros de reprojeção em `results/calibration/`, `results/tables/` e `results/figures/`.
2. [`notebooks/02_opencv_calibration.ipynb`](notebooks/02_opencv_calibration.ipynb) executa as calibrações padrão e restrita do OpenCV. Seus resultados são salvos em `results/opencv/`.
3. [`notebooks/03_intrinsics_comparison.ipynb`](notebooks/03_intrinsics_comparison.ipynb) ajusta as matrizes do ARKit à orientação e à resolução das fotografias HEIC e produz as comparações em `results/comparison/`.

Os dois primeiros notebooks precisam das fotografias HEIC. O terceiro utiliza os resultados das calibrações e os arquivos JSON já presentes em `results/arkit/`. Os notebooks foram executados com OpenCV 5.0.0 e utilizam NumPy, SciPy, pandas, Matplotlib, Pillow, `pillow-heif` e Jupyter/IPython.

## Coleta com ARKit

O aplicativo iOS em [`arkit/CameraIntrinsicsCollector/`](arkit/CameraIntrinsicsCollector/) foi desenvolvido em Swift para coletar as matrizes intrínsecas fornecidas pelo ARKit nos mesmos dispositivos. Ele descarta os primeiros 30 quadros, coleta 120 amostras por dispositivo e exporta as amostras e suas estatísticas para arquivos JSON. Os dados utilizados na comparação estão em `results/arkit/`.

A matriz do ARKit corresponde a uma resolução diferente daquela das fotografias HEIC. Por isso, o terceiro notebook transforma essa matriz antes da comparação. A matriz transformada é utilizada como referência fornecida pelo sistema, sem ser tratada como valor exato dos parâmetros das fotografias HEIC.

## Fontes principais

1. [Zhang, *A Flexible New Technique for Camera Calibration*](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/tr98-71.pdf).
2. [Documentação de calibração de câmeras do OpenCV 5.0](https://docs.opencv.org/5.0/main_modules/calib.html).
3. [Padrão de tabuleiro do OpenCV](https://github.com/opencv/opencv/blob/5.x/doc/pattern.png).
4. [Documentação de `ARCamera.intrinsics` da Apple](https://developer.apple.com/documentation/arkit/arcamera/intrinsics).
