# Tracky

<p align="center">
 <img src="https://github.com/Shopify/tracky/blob/main/readme_images/logo.png" width="300"/>
 <p align="center">
  <em>Record an ARKit session for reconstruction in Blender</em>
 </p>
</p>


## Background

We developed this tool because we wanted to experiment with new AR ideas
faster. By capturing an ARKit session (including its depth data, its
segmentation masks, all of its positional and orientation streams, stereo
microphone audio, and any detected planes) we can reconstruct it in Blender.
Once in Blender, we can quickly iterate on concepts and see the results as they
would look in an ARKit session.


## Prerequisites

* XCode 14.2 or higher
* Blender 2.8 or higher
* An iPhone or iPad with LiDAR


## Build

1. Open the `Tracky.xcodeproj` XCode Project:

<p align="center">
 <img src="https://github.com/Shopify/tracky/blob/main/readme_images/xcodeproj.png" width="600"/>
</p>

2. Plug in a device and select it as the target:

<p align="center">
 <img src="https://github.com/Shopify/tracky/blob/main/readme_images/iphoneselection.png" width="600"/>
</p>

3. Hit play to build it:

<p align="center">
 <img src="https://github.com/Shopify/tracky/blob/main/readme_images/build.png" width="600"/>
</p>


## Install (Blender)

Tracky outputs `.bren` files with all of the recorded data from the ARKit
capture. This file can be imported into Blender via the use of the included
Blender plugin.

1. Open Blender Preferences:

<p align="center">
 <img src="https://github.com/Shopify/tracky/blob/main/readme_images/blenderprefs.png" width="600"/>
</p>

2. Navigate to the Add-ons section:

<p align="center">
 <img src="https://github.com/Shopify/tracky/blob/main/readme_images/addons.png" width="600"/>
</p>

3. Click the "Install..." button:

<p align="center">
 <img src="https://github.com/Shopify/tracky/blob/main/readme_images/installbutton.png" width="600"/>
</p>

4. Navigate to the `BrenImporter/bren_importer.py` file from this checkout:

<p align="center">
 <img src="https://github.com/Shopify/tracky/blob/main/readme_images/brenimporter.png" width="600"/>
</p>

5. Click the "Install Add-on" button:

<p align="center">
 <img src="https://github.com/Shopify/tracky/blob/main/readme_images/installaddon.png" width="600"/>
</p>

6. **Important:** check the box to enable the add-on:

<p align="center">
 <img src="https://github.com/Shopify/tracky/blob/main/readme_images/checkbox.png" width="600"/>
</p>

You're all set! Now you can import your `.bren` files output by the Tracky app.


## Usage

1. Launch `Tracky` on your iOS device:

<p align="center">
 <img src="https://github.com/Shopify/tracky/blob/main/readme_images/launchtracky.gif" width="200"/>
</p>

2. Tap the record button (after waiting for the app to find tracking planes):

<p align="center">
 <img src="https://github.com/Shopify/tracky/blob/main/readme_images/taprecord.gif" width="200"/>
</p>

3. Use the `Files` app to navigate to the `Tracky` directory, and transfer your latest recording to a computer with Blender installed:

<p align="center">
 <img src="https://github.com/Shopify/tracky/blob/main/readme_images/transfertodesktop.gif" width="200"/>
</p>

4. Import the `.bren` file in Blender:

<p align="center">
 <img src="https://github.com/Shopify/tracky/blob/main/readme_images/importinblender.gif" width="600"/>
</p>


## Demo

https://user-images.githubusercontent.com/1228/221047283-e52dea84-1652-4238-b68a-1b0e5f07f640.mp4
