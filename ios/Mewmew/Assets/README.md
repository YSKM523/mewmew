# 猫 Rive 资源契约

将美术方交付的 `cat.riv` 放在本目录：

```text
ios/Mewmew/Assets/cat.riv
```

工程会在打包后的主 Bundle 中查找 `cat.riv`。资源不存在、文件无法加载，
或画板/状态机不符合下述契约时，应用会自动使用现有 SwiftUI 内置猫绘制。

## 固定名称

- Artboard：`Cat`（正方形，建议 512×512）
- State Machine：`CatState`

## State Machine Inputs

| 输入名 | 类型 | 取值与含义 |
| --- | --- | --- |
| `mood` | Number | `0` = happy（精神），`1` = content（平静），`2` = sleepy（打盹） |
| `outfit` | Number | `0` = none（无），`1` = bell（铃铛项圈），`2` = glasses（圆眼镜） |
| `feed` | Trigger | 喂食动画，建议约 1.2 秒 |
| `levelUp` | Trigger | 升级开心动画，建议约 1.5 秒 |

输入名称、类型和值属于稳定的工程契约。替换美术资源时保持它们不变，即可
无需修改代码自动启用 Rive 渲染。
