# Recordy

<p align="center">
 <img src="https://github.com/Shopify/recordy/blob/main/readme_images/logo.png" width="300"/>
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

1. Open the `Recordy.xcodeproj` XCode Project:

<p align="center">
 <img src="https://github.com/Shopify/recordy/blob/main/readme_images/xcodeproj.png" width="600"/>
</p>

2. Plug in a device and select it as the target:

<p align="center">
 <img src="https://github.com/Shopify/recordy/blob/main/readme_images/iphoneselection.png" width="600"/>
</p>

3. Hit play to build it:

<p align="center">
 <img src="https://github.com/Shopify/recordy/blob/main/readme_images/build.png" width="600"/>
</p>


## Install (Blender)

Recordy outputs `.bren` files with all of the recorded data from the ARKit
capture. This file can be imported into Blender via the use of the included
Blender plugin.

1. Open Blender Preferences:

<p align="center">
 <img src="https://github.com/Shopify/recordy/blob/main/readme_images/blenderprefs.png" width="600"/>
</p>

2. Navigate to the Add-ons section:

<p align="center">
 <img src="https://github.com/Shopify/recordy/blob/main/readme_images/addons.png" width="600"/>
</p>

3. Click the "Install..." button:

<p align="center">
 <img src="https://github.com/Shopify/recordy/blob/main/readme_images/installbutton.png" width="600"/>
</p>

4. Navigate to the `BrenImporter/bren_importer.py` file from this checkout:

<p align="center">
 <img src="https://github.com/Shopify/recordy/blob/main/readme_images/brenimporter.png" width="600"/>
</p>

5. Click the "Install Add-on" button:

<p align="center">
 <img src="https://github.com/Shopify/recordy/blob/main/readme_images/installaddon.png" width="600"/>
</p>

6. **Important:** check the box to enable the add-on:

<p align="center">
 <img src="https://github.com/Shopify/recordy/blob/main/readme_images/checkbox.png" width="600"/>
</p>

You're all set! Now you can import your `.bren` files output by the Recordy app.