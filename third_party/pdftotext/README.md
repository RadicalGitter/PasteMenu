# pdftotext

PasteMenu bundles `pdftotext.exe` from the Xpdf tools by Glyph & Cog, LLC for local PDF text extraction.

The executable is stored here:

```text
third_party\pdftotext\pdftotext.exe
```

When `build_pastemenu.bat` runs, it copies that file to:

```text
dist\tools\pdftotext.exe
```

PasteMenu also looks for `pdftotext.exe` in the project root, `tools`, `bin`, this folder, the compiled app's `dist\tools`, and PATH.

Source:

```text
https://dl.xpdfreader.com/xpdf-tools-win-4.06.zip
```

Licensing:

- Xpdf tools are distributed under GPL licensing.
- `COPYING.txt` and `COPYING3.txt` are included from the upstream archive.
- Keep these files with any PasteMenu release that includes `pdftotext.exe`.
