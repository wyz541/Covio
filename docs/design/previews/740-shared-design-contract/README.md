# Issue 740 shared design contract previews

## Evidence

- Date: `2026-11-10`
- Device: Windows x64 development workstation
- OS: Windows 11 25H2, build `26200.9711`
- UI scale: `1.5`
- Page: Workspace
- State: seeded workspace data
- Commit: `e670315`
- Change: Windows interface font uses Segoe UI Variable with Segoe UI fallback.

## Result

The font change keeps the documented text hierarchy.
The semantic tokens keep the light and dark surface hierarchy.

## After

| Light | Dark |
| --- | --- |
| [after-workbench-light.png](after-workbench-light.png) | [after-workbench-dark.png](after-workbench-dark.png) |

## Before

The previous Windows baseline images are in
[700-windows-macos-parity](../700-windows-macos-parity/).

- [before-workbench-light.png](../700-windows-macos-parity/before-workbench-light.png)
- [before-workbench-dark.png](../700-windows-macos-parity/before-workbench-dark.png)

## Commands

```sh
bash scripts/test-windows-rust.sh
```

The script generated both after images.
