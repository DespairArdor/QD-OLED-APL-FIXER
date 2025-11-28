# ReShade EOTF Boost (OLED APL Fix)

A ReShade shader designed to emulate the "EOTF Boost" feature found on MSI QD-OLED monitors. It dynamically adjusts gamma and brightness in real-time to compensate for the aggressive ABL (Auto Brightness Limiter) dimming on QD-OLED screens during bright scenes.

**Target Audience:** Users of WOLED / QD-OLED monitors (Alienware, ASUS, Samsung) who feel the screen gets too dark in high-APL scenes (sunny days, snow, bright skies).

## ✨ Features

* **Dynamic APL Detection:** Uses grid sampling to accurately measure average screen brightness in real-time.
* **Smart Compression (Soft Knee):** Unlike simple gamma boosters, this uses a "soft shoulder" compression curve. It boosts mid-tones while protecting high-luminance details (clouds, sun, fire) from clipping.
* **Color Safe Mode:** Separates Luma and Chroma to prevent colors from washing out or shifting hues when brightness is boosted.
* **Shadow Protection:** "Anchors" deep blacks to zero, ensuring the boost doesn't ruin your OLED's perfect black levels.
* **Smooth Transition:** Features time-based smoothing to prevent brightness flickering during rapid camera movements.

## 📥 Installation

1.  Download and install [ReShade](https://reshade.me/) for your game.
2.  Download the `EOTF_Boost.fx` file from this repository.
3.  Place the file into your game's shader folder:
    * Example: `\GameFolder\reshade-shaders\Shaders\`
4.  Launch the game, open the ReShade overlay (Home key), and enable **EOTF Boost**.

## ⚙️ Configuration Guide

* **Boost Strength:** Controls how much the mid-tones are lifted. Higher values = brighter image but more ABL engagement.
* **Compression Start (Soft Knee):** The most important setting.
    * `0.80` (Default): Allows brightness to ramp up freely up to 80%, then gently compresses the highlights. Keeps the "punch" while saving details.
    * `1.0`: No compression (maximum brightness, but may clip white details).
* **APL Trigger:** The percentage of screen brightness required to activate the boost. `0.25` (25%) is recommended to avoid boosting dark scenes unnecessarily.
* **Shadow Protection:** Keep this around `1` to ensure your blacks stay inky black.

## 📊 On-Screen Display (OSD)

The shader includes a built-in OSD in the top-right corner showing:
* **Current APL %:** The real-time brightness of the scene.
* **Status Color:**
    * **White:** Boost is inactive (Dark scene).
    * **Green:** Boost is active (Bright scene).

 <img width="1274" height="222" alt="image" src="https://github.com/user-attachments/assets/6e61c305-0e51-4ef7-b55b-71bc7dbf56dd" />
Example setting for Horizon Forbidden West default apl compensation on g80sd hdr peak 1000

 <img width="1313" height="247" alt="image" src="https://github.com/user-attachments/assets/38d246bc-1b66-41f3-a2a4-89b0eed3ce47" />
Example setting for Horizon Forbidden West extreme apl compensation on g80sd hdr peak 1000

## ⚠️ Disclaimer

This is a software-based post-processing effect. While it visually compensates for dimming, it cannot bypass the physical power limits of your panel. Use responsibly. I am not responsible for any potential burn-in or hardware issues, although this shader is generally safe as it only manipulates the image signal.

## 📄 License

MIT License. Feel free to modify and share.
