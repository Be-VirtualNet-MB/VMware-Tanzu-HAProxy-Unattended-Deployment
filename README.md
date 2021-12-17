# VMware-Tanzu-HAProxy-Unattended-Deployment

This repository is for a VMware Tanzu HAProxy Unattended Deployment Script.
Code is optimized for deploying the Tanzu for vSphere (TKGs) HAProxy image provided by VMware.

## HAProxy Image

The HAProxy image can be found on the following location: <https://github.com/haproxytech/vmware-haproxy>
The code was tested with version 0.2.0.

## Guidance

- Download the HAProxy Image (v0.2.0).
- Move the HAProxy image to the default location: C:\Temp.
- Change all the variables depending on your environment in the script (HAProxy_Tanzu_Deployment.ps1).
- Run the script (HAProxy_Tanzu_Deployment.ps1) in PowerShell.
- Answer the questions that are asked by the script.
