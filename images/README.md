# Imagens de calibração

As imagens originais utilizadas na calibração foram capturadas em formato `.HEIC` e não são rastreadas pelo Git.

Para reproduzir os experimentos, os conjuntos de imagens devem ser armazenados localmente seguindo a estrutura:

```text
images/
├── iphone15/
├── ipad9/
└── pattern.png
```

O arquivo `images/pattern.png` corresponde ao padrão de calibração disponibilizado no repositório oficial do OpenCV:

https://github.com/opencv/opencv/blob/5.x/doc/pattern.png

O padrão foi impresso em uma folha A4 utilizando escala de **100% (tamanho real)**, sem ajuste automático à página, de modo a preservar suas dimensões originais.

---

# Calibration Images

The original images used for camera calibration were captured in `.HEIC` format and are not tracked by Git.

To reproduce the experiments, the image datasets should be stored locally using the following structure:

```text
images/
├── iphone15/
├── ipad9/
└── pattern.png
```

The `images/pattern.png` file corresponds to the calibration pattern provided in the official OpenCV repository:

https://github.com/opencv/opencv/blob/5.x/doc/pattern.png

The pattern was printed on an A4 sheet using **100% scale (actual size)**, without automatic fit-to-page scaling, in order to preserve its original dimensions.