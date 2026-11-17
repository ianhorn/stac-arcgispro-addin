# Installation

## Which download do I need?

Esri ties each ArcGIS Pro release to a specific .NET version, so there are two builds of the same
add-in:

| You have               | Download                           | Target framework  |
|-------------------------|-------------------------------------|--------------------|
| ArcGIS Pro 3.6.x         | `StacProAddin-3.6.x.esriAddinX`     | `net8.0-windows`   |
| ArcGIS Pro 3.7 or later  | `StacProAddin-3.7.x.esriAddinX`     | `net10.0-windows`  |

Pro 3.6.x hosts .NET 8 and Pro 3.7+ hosts .NET 10; a build targeting the wrong one won't load. Both
files come from the same source and the same `Config.daml` (`desktopVersion="3.6.0"`, so the
manifest is accepted by 3.6 and later).

## Download the pre-built add-in

[![Downloads](https://img.shields.io/github/downloads/ianhorn/stac-arcgispro-addin/total.svg)](https://github.com/ianhorn/stac-arcgispro-addin/releases)

No Visual Studio or source build required -- download the `.esriAddinX` that matches your ArcGIS
Pro version, then double-click it (or copy it to `%LocalAppData%\ESRI\ArcGISPro\AssemblyCache`) to
install it through ArcGIS Pro's normal Add-In Manager flow:

- [Download for ArcGIS Pro 3.6.x](https://github.com/ianhorn/stac-arcgispro-addin/releases/latest/download/StacProAddin-3.6.x.esriAddinX)
- [Download for ArcGIS Pro 3.7 or later](https://github.com/ianhorn/stac-arcgispro-addin/releases/latest/download/StacProAddin-3.7.x.esriAddinX)

These links always point at the latest [GitHub Release](https://github.com/ianhorn/stac-arcgispro-addin/releases),
rebuilt from `master` whenever a new release is cut (see `tools/release.ps1`); see
[Build from source](#build-from-source) below if you'd rather build it yourself.

## Requirements

- **ArcGIS Pro 3.6** or later (the add-in manifest targets `desktopVersion="3.6.0"`).
- **ArcGIS Pro SDK for .NET** installed (adds the Visual Studio project templates and the
  `Esri.ProApp.SDK.Desktop.targets` build integration this project relies on).
- **Visual Studio 2022 (17.13+) or 2026 ("18")** to build from source.

## Build from source

1. Clone the repository:

    ```bash
    git clone https://github.com/ianhorn/stac-arcgispro-addin.git
    ```

2. Open `StacProAddin.sln` (or `StacProAddin.slnx`) in Visual Studio.
3. Build the `StacProAddin` project (Debug or Release). The ArcGIS Pro SDK's build targets
   package the compiled assembly, `Config.daml`, and the toolbar images into an `.esriAddinX` file
   and register it with ArcGIS Pro automatically.
4. Press **F5** (or **Start**) to launch ArcGIS Pro with the add-in already loaded, or just open
   ArcGIS Pro normally -- once built, the add-in stays registered.

!!! tip "No Visual Studio?"
    You only need the compiled `.esriAddinX` file to *use* the add-in -- grab one from
    [Download the pre-built add-in](#download-the-pre-built-add-in) above instead of building from
    source.

## Code signing (optional)

The project can Authenticode-sign the compiled assembly before packaging. Run the one-time setup:

```powershell
powershell -ExecutionPolicy Bypass -File tools\setup-code-signing.ps1
```

Signing is on by default; disable it for a single build with:

```bash
dotnet build -p:SignAddin=false
```

## Verifying the install

Open ArcGIS Pro and look for the **STAC Browser** ribbon tab with a **STAC Search** button. If
it's missing, confirm the build succeeded with no errors and that ArcGIS Pro was restarted after
the first build.

## Building for another ArcGIS Pro version

The project file targets `net8.0-windows` (Pro 3.6.x). The references to ArcGIS Pro's assemblies are
direct file paths (`C:\Program Files\ArcGIS\Pro\bin\...`), not a versioned NuGet package, and are
not copied into the output, so the 3.7.x build is made from the same `.csproj` by overriding the target
framework on the command line, without needing Pro 3.7 installed:

```
"C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe" StacProAddin.csproj -t:Restore -p:Configuration=Release -p:TargetFramework=net10.0-windows
"C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe" StacProAddin.csproj -p:Configuration=Release -p:TargetFramework=net10.0-windows
```

`tools/release.ps1` does both builds and publishes them as the two release assets.
