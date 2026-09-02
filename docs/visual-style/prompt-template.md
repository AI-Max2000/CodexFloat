# GitHub 日常发布图 · 提示词模板

默认使用内置 ImageGen。本模板是可读的创作约束，不是脚本或指定模型 API；不要静默切到收费 API。

## 每次先填这六项

```text
项目名：
用途：发版首图 / 功能图解 / 操作对照
已核实功能（含源码或文档依据）：
要渲染的文字（逐字列出）：
主体图示和信息对应关系：
必须保留的限制 / 示例标记：
```

## 可复用母提示词

```text
Use case: ads-marketing / infographic-diagram.
Create one polished Simplified Chinese GitHub product feature illustration.
Image 1 is the user's approved STYLE REFERENCE, not an edit target.
Keep its warm off-white, graphite typography, muted green / restrained amber,
thin neutral dividers, generous whitespace, and premium flat native-app feeling.
Do not copy unrelated content from the reference.

Canvas: landscape 1536 × 1024, 3:2. Keep all content within a 64px safe area.
Typography: clear modern Chinese sans-serif, bold graphite headline,
medium-gray subtitle, short readable supporting labels.
Structure: small project name and category at the top, one strong headline,
one short explanation, one coherent main product diagram, a restrained row
of 2–4 capability labels, then the necessary disclosure.

Project: <PROJECT NAME>
Headline, verbatim: "<HEADLINE>"
Subtitle, verbatim: "<SUBTITLE>"
Other exact copy: <LABELS>
Main diagram: <VERIFIED STRUCTURE AND BEHAVIOR>
Required disclosure, verbatim: "<DISCLOSURE>"

Preserve feature meaning, proportions and state semantics.
This is an explanatory illustration, not a claimed real application screenshot.
Do not add features, entitlement claims, metrics, dates, testimonials, official
endorsements, third-party logos, QR codes or decorative copy.
No neon colors, heavy gradients, glossy 3D, large shadows or ornamental charts.
Keep every Chinese character readable and inside its bounds.
```

将当前仓库的 `docs/Images/codex-float-0.2.0-feature.png` 作为风格参考传入；先查看文件，不能只在提示词中写路径而不提供图像。

## 迭代原则

一次只改一个明确问题，例如错字、错误比例或裁切。再次说明哪些部分必须保持不变，避免整张图在修正中换风格。生成结果必须人工查看，不能只凭文件存在就发布。原生截图、真实数据和生成示意分开存放；需要严格真实性的材料以原始导出为准。
