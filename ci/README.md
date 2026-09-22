# CI 使用说明

本仓库的 CI 由两套系统组成，但**所有安装 / 启动 / 测试 / 报告逻辑都收敛在仓库根目录的
`test.sh`** 中，CI 配置只负责声明矩阵和环境变量，避免重复步骤漂移。

## 统一入口 `test.sh`

| 命令 | 作用 |
| --- | --- |
| `./test.sh install` | 创建 venv 并安装依赖（支持 `USE_GIT`、`SCRAPYD_VERSION` 变体） |
| `./test.sh env <variant>` | 输出 `none/sqlite/postgresql/mysql` 变体的环境变量（配合 `eval`） |
| `./test.sh wait-db` | 等待 `DATABASE_URL` 指向的数据库就绪（sqlite 时为 no-op） |
| `./test.sh scrapyd` | 写入带认证的 `scrapyd.conf` 并启动 Scrapyd |
| `./test.sh test` | flake8 + coverage/pytest（缺少插件时自动降级） |
| `./test.sh report` | 生成 coverage report/html/xml（并按需上传 coveralls） |
| `./test.sh allure` | 生成 Allure 报告（需设置 `ALLURE_VERSION`） |
| `./test.sh check` | 运行 `ci/check_matrix.py` 校验两套 CI 矩阵完整性 |
| `./test.sh all` | install + wait-db + scrapyd + test + report |

本地一键复现 CI（需要 Python 3 与网络）：

```bash
./test.sh all                      # 基础测试（默认 sqlite）
USE_GIT=1 ./test.sh all            # git 版 Scrapy/Scrapyd/LogParser
SCRAPYD_VERSION=1.4.3 ./test.sh all
eval "$(./test.sh env sqlite)" && ./test.sh all
DRY_RUN=1 ./test.sh install        # 只打印将执行的命令
```

更多可调环境变量见 `test.sh` 文件头注释。

## 测试矩阵

GitHub Actions（`.github/workflows/tests.yml`）与 CircleCI（`.circleci/config.yml`）
覆盖同一组关键组合：

| 组合 | Python | Scrapyd | 依赖 | 数据库 |
| --- | --- | --- | --- | --- |
| 基础测试 | 3.8 / 3.9 / 3.10 / 3.11 / 3.12 / 3.13 | latest | PyPI | 默认 sqlite |
| Scrapyd 旧版 | 3.9 / 3.12 | 1.4.3 | PyPI | 默认 sqlite |
| SQLite 变体 | 3.10 | latest | PyPI | sqlite（自定义 `DATA_PATH`/`DATABASE_URL`） |
| PostgreSQL 变体 | 3.10 | latest | PyPI | postgresql |
| MySQL 变体 | 3.10 | latest | PyPI | mysql |
| git 依赖 + PostgreSQL | 3.10 | git HEAD | git | postgresql（兼 Allure 报告） |
| git 依赖 + MySQL | 3.10 | git HEAD | git | mysql |

## 矩阵自检

`ci/check_matrix.py` 是矩阵的**单一事实来源**：`REQUIRED_COMBOS` 列出必须覆盖的组合，
脚本会解析两套 CI 配置并断言两边都覆盖全部组合，同时检查配置确实经由 `./test.sh` 执行。
该检查作为 `matrix-check` 任务在两个 CI 系统中都会运行；本地可随时执行：

```bash
./test.sh check
```

新增矩阵组合时，请先更新 `ci/check_matrix.py` 中的 `REQUIRED_COMBOS`，
再同步更新两套 CI 配置与本文件表格，否则自检会失败。
