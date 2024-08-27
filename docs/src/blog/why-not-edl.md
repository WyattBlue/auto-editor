---
title: Why Auto-Editor Doesn't Support EDL Files
author: WyattBlue
date: September 10, 2023
desc: The EDL format doesn't have a widespread standard. This, among other issues, makes it impractical to support.
---

The EDL format is simple enough to write a timeline exporter. Writing an "auto-editor v1" to EDL converter should be a simple job. However, it wouldn't be a good idea for auto-editor to support an "EDL" format because every program interprets EDL in different ways. 

Worse, there is no standard way to tell the difference between the dialects. The lack of widely accepted standards makes the EDL format impracticable to implement.

Could auto-editor support exports to the "CMX 3600" or "Grass Valley" dialects specifically? 
Yes; however, how many users are clamoring for these specifically? Not many, and why should they? Auto-Editor already supports fcp7 and fcp11 (among others), formats that really do have demand, documentation, specs, and wide spread industry use.

