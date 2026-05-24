# GitBook 中文站点设置

本仓库只保存 Markdown 内容。GitBook 的原生语言按钮和语言选择器不通过仓库中的配置文件启用，而是通过 GitBook UI 中的站点 variants/spaces 管理。

要将 `docs/zh` 内容作为中文文档发布，Ayaz 需要通过 GitBook 创建或连接一个中文 space，并将其设为现有文档站点的中文 variant。

## 建议设置

- 英文 space 指向 `docs`
- 中文 space 指向 `docs/zh`
- 中文 variant 名称：`简体中文`
- 语言代码：`zh` 或 `zh-CN`
- 默认语言：英文

设置完成后，GitBook 会在站点中显示语言切换入口。仓库内不需要额外的 redirect 文件或自定义选择器。
