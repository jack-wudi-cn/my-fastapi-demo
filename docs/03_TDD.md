# 技术设计文档 (TDD) - Invoice-AI MVP

**文档版本**：v0.1.0
**对应 PRD**：v0.1.0
**主导角色**：架构师 (Architect)

## 1. 技术栈选型 (Tech Stack)
考虑到本项目是 MVP（最小可行性产品），需在保证功能的前提下，尽可能降低运维和部署成本，选型如下：
- **语言**：Python 3.11（生态完善，AI 库多）。
- **Web 框架**：FastAPI（原生异步，自动生成 Swagger 接口文档）。
- **数据库**：SQLite 3（免安装、单文件落盘，非常适合 MVP 和本地开发。后续可平滑迁移至 PostgreSQL）。
- **ORM 框架**：SQLAlchemy 2.0（Python 事实上的 ORM 标准，屏蔽底层 SQL 差异）。
- **配置管理**：`pydantic-settings` + `.env` 文件（防止敏感信息硬编码）。

## 2. 系统架构分层 (Layered Architecture)
采用经典的分层架构，严禁跨层调用。好处是：业务逻辑（Service）被剥离出来，以后无论是通过 HTTP 接口调用，还是通过后台定时任务调用，都可以复用。
- **API 层 (Routers)**：只负责接收 HTTP 请求、做 Pydantic 数据校验、返回 HTTP 响应。
- **业务层 (Services)**：核心业务逻辑（提取、校验、状态流转）都在这里。
- **数据层 (Models / CRUD)**：负责与 SQLite 数据库交互。
- **公共层 (Core)**：配置读取、数据库连接池初始化。

## 3. 数据库设计 (Database Schema)

### 3.1 核心表：`invoices` (发票任务表)
这是系统的核心存储，所有提取的数据和状态都在这里。

| 字段名 | 数据类型 | 约束/索引 | 说明 |
| :--- | :--- | :--- | :--- |
| `id` | Integer | Primary Key, 自增 | 主键 |
| `raw_text` | Text | 必填 | 用户提交的原始发票文本 |
| `raw_text_hash` | String(32) | **UNIQUE**, Index | 原文的 MD5 哈希，用于 PRD 要求的幂等防抖（5秒内相同文本不重复建单） |
| `invoice_number`| String(50) | **UNIQUE**, Index | 提取出的发票号。唯一索引用于防止并发重复报销 |
| `amount` | Float | 可空 | 提取出的金额 |
| `invoice_date` | String(20) | 可空 | 提取出的发票日期 |
| `status` | String(20) | 必填, Index | 状态机（PENDING/EXTRACTING/REVIEWING/APPROVED/REJECTED/FAILED） |
| `is_duplicate` | Boolean | 默认 False | 风控标记：是否重复报销 |
| `is_large_amount`| Boolean | 默认 False | 风控标记：是否大额 (>10000) |
| `review_note` | Text | 可空 | 财务审核时的批注 |
| `created_at` | DateTime | 默认当前时间 | 任务创建时间 |
| `updated_at` | DateTime | 自动更新 | 最后更新时间 |

### 3.2 架构设计决策（Why？）
1. **为什么要加 `raw_text_hash`？** 如果前端手抖连点两次提交，或者网络重试。系统可以通过计算这段文本的 MD5 值，查库发现 5 秒内已经有相同文本，直接返回上次结果，避免浪费算力。
2. **为什么 `invoice_number` 要加 UNIQUE 索引？** 如果两个请求同时进来，都提取到了同一个发票号。应用层查库可能都没查到，然后同时插入。数据库加唯一索引，能直接在最底层拦截并发脏写（报错后应用层捕获，标记 `is_duplicate=True`）。