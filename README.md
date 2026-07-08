
# Field-Image-Calibration

[![Software Repository](https://img.shields.io/badge/iCalibrateImages_v1.1-Windows&macOS&Linux-blue)](https://www.erda.au.dk/archives/b7374394d4a96cd79be717637ae7d11f/published-archive.html)
[![Supplementary Material](https://img.shields.io/badge/Supplementary_Material-ERDA-blue)](https://www.erda.au.dk/archives/b40fa172f2e5f7a58ea84ccf81b7ab1c/published-archive.html)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21192432.svg)](https://doi.org/10.5281/zenodo.21192432)


## Overview

This repository contains the source code and supporting resources for **[iCalibrateImages](https://www.erda.au.dk/archives/9d4f9eedbf4aca9b133d2925df21c6e9/published-archive.html)**, a desktop application for color calibration of RAW images using a **ColorChecker** reference target.

Accurate color calibration is essential for field photography and image-based scientific analyses, particularly when images are acquired under varying lighting conditions or with different digital cameras. It enables users to standardize image colors, producing consistent and comparable outputs across cameras, sensors, and field campaigns.

The software provides an intuitive workflow that allows users to perform reliable color correction without requiring advanced expertise in image processing. It supports a wide range of digital cameras and RAW image formats, making it suitable for diverse field and laboratory applications.



## Download

Available for **Windows**, **macOS**, and **Linux**. Precompiled installation packages can be downloaded from the **ERDA repository**:

🔗 https://www.erda.au.dk/archives/9d4f9eedbf4aca9b133d2925df21c6e9/published-archive.html

The repository also includes sample images that demonstrate the calibration workflow and can be used to validate software performance.
Just use the default installation options and it should work out of box. 
Note that there is a readme file for the macOS version that provides additional instructions for installation  and ensure you follow the installation instructions to have the correct JAVA runtime. 
The starting up can be slow during installation or first time running. Please be patient.

## Image post-processing workflow
A [random forest classifier](https://www.erda.au.dk/archives/b40fa172f2e5f7a58ea84ccf81b7ab1c/GlacierLab/Production/iCalibrateImages/TCsupplementary/rf_training_output/vegetation_classifier_rf.pkl) is available on [ERDA](https://www.erda.au.dk/archives/b40fa172f2e5f7a58ea84ccf81b7ab1c/published-archive.html) to automatically classify the surface ice to derive the fractional cryoconite cover. 
Download the classifier and run [src\applyClassifier.py](src/applyClassifier.py) to apply the classifier to the calibrated images.
Then [src\classification_analysis_two_classes.m](src/classification_analysis_two_classes.m) can be used to analyze the classification results and derive the fractional cryoconite cover.

The results in the manuscript are derived from the calibrated images using the classifier and are available in [stat\LAIs.xlsx](stat/LAIs.xlsx). The script [src\darkening_analysis.py](src/darkening_analysis.py) is made to investigate the association between glacier algae, fractional cryoconite cover, and the darkening of the glacier surface. It can be used to reproduce the figures in the manuscript.

## Guide for capturing images for calibration
A tutorial on how to capture images for calibration is available in the [doc\field_image_calibration_sample_tutorial.pdf](doc/field_image_calibration_sample_tutorial.pdf). It provides detailed instructions on how to photograph the ColorChecker target under various lighting conditions and camera settings to ensure optimal calibration results.

## Citation

If you use **iCalibrateImages** in your research, please cite the associated publication.

```markdown
Shunan Feng (2026) “glacier-lab/Field-Image-Calibration: iCalibrateImages”. Zenodo. doi:10.5281/zenodo.21192432.
```

Latex
```
@software{shunan_feng_2026_21192432,
  author       = {Shunan Feng},
  title        = {glacier-lab/Field-Image-Calibration:
                   iCalibrateImages
                  },
  month        = jul,
  year         = 2026,
  publisher    = {Zenodo},
  version      = {v1.0-beta},
  doi          = {10.5281/zenodo.21192432},
  url          = {https://doi.org/10.5281/zenodo.21192432},
}
```


