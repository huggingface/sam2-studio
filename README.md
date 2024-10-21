# SAM2 Studio

This is a Swift demo app for SAM 2 Core ML models.

![UI Screenshot](screenshot.png)

SAM 2 (Segment Anything in Images and Videos), is a collection of foundation models from FAIR that aim to solve promptable visual segmentation in images and videos. See the [SAM 2 paper](https://arxiv.org/abs/2408.00714) for more information.

## Quick Start ⚡️

Download the compiled version [here!](https://huggingface.co/coreml-projects/sam-2-studio).

## How to Use

If you prefer to compile it yourself or want to use a larger model, simply download the repo, compile with Xcode and run. 
The app comes with the Small version of the model, but you can replace it with one of the supported models:

- [SAM 2.1 Tiny](https://huggingface.co/apple/coreml-sam2.1-tiny)
- [SAM 2.1 Small](https://huggingface.co/apple/coreml-sam2.1-small)
- [SAM 2.1 Base](https://huggingface.co/apple/coreml-sam2.1-baseplus)
- [SAM 2.1 Large](https://huggingface.co/apple/coreml-sam2.1-large)

For the older models, please check out the [Apple](https://huggingface.co/apple) organisation on HuggingFace.

This demo supports images and videos. 

### Selecting Objects

- You can select one or more _foreground_ points to choose objects in the image. Each additional point is interpreted as a _refinement_ of the previous mask.
- Use a _background_ point to indicate an area to be removed from the current mask.
- You can use a _box_ to select an approximate area that contains the object you're interested in.

### Video Segmentation with Text Prompts

To use the video segmentation feature with text prompts, follow these steps:

1. Import a video file into the app.
2. Enter a text prompt describing the object you want to segment in the video.
3. The app will process the video frames and generate segmentation masks based on the text prompt.
4. You can view and edit the segmentation results frame by frame.

## Converting Models

If you want to use a fine-tuned model, you can convert it using [this fork of the SAM 2 repo](https://github.com/huggingface/segment-anything-2/tree/coreml-conversion). Please, let us know what you use it for!

## Feedback and Contributions

Feedback, issues and PRs are welcome! Please, feel free to [get in touch](https://github.com/huggingface/sam2-swiftui/issues/new).

## Citation

To cite the SAM 2 paper, model, or software, please use the below:

```
@article{ravi2024sam2,
  title={SAM 2: Segment Anything in Images and Videos},
  author={Ravi, Nikhila and Gabeur, Valentin and Hu, Yuan-Ting and Hu, Ronghang and Ryali, Chaitanya and Ma, Tengyu and Khedr, Haitham and R{\"a}dle, Roman and Rolland, Chloe and Gustafson, Laura and Mintun, Eric and Pan, Junting and Alwala, Kalyan Vasudev and Carion, Nicolas and Wu, Chao-Yuan and Girshick, Ross and Doll{\'a}r, Piotr and Feichtenhofer, Christoph},
  journal={arXiv preprint arXiv:2408.00714},
  url={https://arxiv.org/abs/2408.00714},
  year={2024}
}
```



