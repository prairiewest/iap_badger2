# iap_badger2

A unified approach to in-app purchases with Solar2D.

Although Solar2D offers an IAP API that is quite similar across the app stores, there are differences depending on whether you are connecting to Apple's App Store, Google Play or through Amazon. IAP Badger attempts to make in-app purchases work closer to the same across all app stores.

## Overview

The iap_badger2 plugin can be used in your Solar2D project.  It provides:

* A simplified set of functions for processing in-app purchases (IAP)
* The ability to write a single piece of IAP code that works across Apple's App Store, Google Play and Amazon
* Makes Google and Amazon stores appear to follow the purchase/restore model adopted by Apple
* A built-in inventory system with basic security for load/saving purchases (if you want it)
* Products can have different names across the range of stores without the need for additional code
* A testing mode, so your IAP functions can be tested on the simulator or a real device without having to contact an actual app store

IAP Badger is wrapper class written in pure lua for Solar2D's Apple store libraries and the Google and Amazon IAP plug-ins.

It's supplied under an MIT license, so fork it and do what you like with it.

## Google Subscription Purchases

If you want to implement Google Subscription in-app purchases then the receipts must be verified using a server, they cannot be verified within your app. You will need to install the code from this other project to your server: https://github.com/prairiewest/verifyreceipt

## Documentation

The code included in this repository is a standard lua library, which can be included in your project and forked/amended as required.

The documentation for IAP Badger can be found in the **iapdocs** folder in this project.

IAP Badger was originally written by [happymongoose](https://github.com/happymongoose). This code is being maintained by [prairiewest](https://github.com/prairiewest).  It started as a fork of the original IAP Badger, however since the upstream repository was no longer maintained this code is now detached.
