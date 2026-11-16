# API 配置

## 一、两种接口

| 类型 | 走哪条路 | Base URL | 模型 | 特殊字段 |
|---|---|---|---|---|
| **DeepSeek 官方**（内置，不可删） | 引擎的 `TavernModelConfig(deepseek: true)` | `https://api.deepseek.com`（引擎会补 `/beta`） | `酒馆设置` 里选的 `deepseek-flash` / `deepseek-v4-pro` | `thinking: {type: enabled/disabled}` |
| **OpenAI 兼容自定义**（可多份） | 引擎的 `TavernModelConfig(deepseek: false)` | 你填的任意前缀，也可以直接填到 `/chat/completions` | 你填的模型名 | 不发 `thinking` |

引擎本身就是按 OpenAI Chat Completions 写的（`packages/dsh_tavern/lib/src/llm/model_client.dart`）：

- 请求：`POST <baseUrl>/chat/completions`，`Authorization: Bearer <key>`；
- 流式：SSE，逐行 `data: {...}`，以 `data: [DONE]` 结束；`delta.content`、
  `delta.reasoning_content`、`delta.tool_calls` 都会被读；
- 非流式：`stream: false` 时读 `choices[0].message`；
- 用量：`usage.prompt_tokens` / `completion_tokens`，缓存命中读
  `prompt_cache_hit_tokens` 或 `prompt_tokens_details.cached_tokens`。

所以「接第三方 / 中转 / 本地模型」不需要改引擎，只需要换 Base URL、Key、模型名。

## 二、界面在哪

首页右上 →「API Key」页：

- 上半部分是 **DeepSeek 官方** Key（存 Android Keystore 支持的 secure storage，
  键名 `deepseek_api_key`，与上游一致）；
- 下半部分「打开 API 配置」进入 `API 配置` 页。

`API 配置` 页：

- 顶部一张「DeepSeek 官方」卡，可直接填 Key 并**激活**；
- 下面是自定义 API 列表，每张卡显示 `Base URL · 模型 · SSE`、有没有 Key、是否「使用中」；
- 「新增」打开编辑面板：名称、类型（OpenAI 兼容 / DeepSeek 方言）、Base URL
  （带常见地址下拉：OpenAI、OpenRouter、SiliconFlow、Moonshot、本地 Ollama/LM Studio）、
  模型、Key、SSE 开关、思考开关，以及 **测试连接**；
- 编辑面板的「测试连接」按真正的请求格式发一条 `ping`（`max_tokens: 8`,
  `stream: false`），成功显示 `OK · 200 · 812 ms`，失败显示状态码与服务端错误
  （Key 与 `Bearer …` 会被打码，最多 400 字）。

## 三、保存与切换

- 元数据（名称、类型、Base URL、模型、SSE、思考）存 `SharedPreferences`，键
  `api_profiles_v1`；当前激活项存 `api_profile_active_v1`；
- Key **不进** SharedPreferences：每个 profile 一把，存在 secure storage 的
  `api_profile_key_<id>`，与 DeepSeek 官方 Key 分开；
- 切换激活项立即生效：`tavern_provider.dart` 监听 `apiProfilesProvider`，重新
  `tavern.configure(...)`，下一回合就走新端点；
- 删除 profile 会一并删掉它的 Key；DeepSeek 官方那张不能删。

## 四、SSE 开关做了什么

`stream = true`（默认）：请求体 `stream: true`（若预设里已写则不覆盖），逐字返回。

`stream = false`：请求体强制 `stream: false`，引擎走「一次返回整段」的分支，
界面在回复到达后整段显示。

引擎侧的改动只有两处（见 `README.md` 的差异表），默认值保证上游行为不变。

## 五、安全

- Key 不出现在日志里：引擎的错误详情会替换掉 Key 与 `Bearer …`
  （`_apiError`），本项目的测试连接同样打码；
- Key 不写进导出文件：`ApiProfile.toJson()` 明确不含 Key；
- 明文 HTTP 仅在你手填 `http://` 时使用（本地 Ollama / LM Studio 常见）；
  正式端点请用 `https://`。

## 六、常见配置示例

| 服务 | Base URL | 模型名示例 |
|---|---|---|
| DeepSeek 官方 | `https://api.deepseek.com` | `deepseek-flash` |
| OpenAI | `https://api.openai.com/v1` | `gpt-4o-mini` |
| OpenRouter | `https://openrouter.ai/api/v1` | `deepseek/deepseek-chat` |
| 硅基流动 | `https://api.siliconflow.cn/v1` | `deepseek-ai/DeepSeek-V3` |
| 月之暗面 | `https://api.moonshot.cn/v1` | `moonshot-v1-8k` |
| 本机 Ollama（模拟器访问宿主机） | `http://10.0.2.2:11434/v1` | `llama3.1` |
| 局域网 LM Studio | `http://192.168.x.x:1234/v1` | 模型页里显示的名字 |

> 说明：除 DeepSeek 官方外，本项目**没有**逐家实测过这些服务的返回格式；
> 引擎只依赖标准 Chat Completions 字段，遇到不标准的中转，先在编辑面板点「测试连接」，
> 再用一回合对话看 `舞台 › 本回合` 的 token 统计是否符合预期。
