# 自动更新 manifest

结论：Updater 验证下载得到的原始 manifest bytes。Manifest 使用 detached Ed25519 签名。

## 边界

| 项目 | 值 |
| --- | --- |
| 渠道 | `internal` |
| 固定仓库 | `wyz541/kmp-Covio` |
| Manifest schema | `1` |
| Signature schema | `1` |
| Updater protocol | `1` |

Manifest 和签名信封来自同一个 GitHub Release。
Updater 不从网页正文读取更新身份。

## 文件

```text
CovioUpdate-<clientVersion>.json
CovioUpdate-<clientVersion>.sig.json
CovioUpdate-<clientVersion>.zip
```

Manifest 使用排序键和紧凑 JSON 生成。
验签不重新序列化 manifest。签名覆盖下载得到的完整文件字节。

## 签名信封

```json
{
  "schemaVersion": 1,
  "manifestSHA256": "<64 lowercase hex characters>",
  "signatures": [
    {
      "keyId": "covio-internal-test",
      "signature": "<base64 Ed25519 signature>"
    }
  ]
}
```

所有声明的 key ID 必须是当前 updater 内置的受信任 key ID。
所有签名必须有效。
Manifest 的 `keyId` 必须出现在签名信封中。

## 校验顺序

```text
原始 manifest bytes
    ↓
manifest SHA-256
    ↓
Ed25519 签名
    ↓
schema、channel 和协议
    ↓
build 与四段 clientVersion
    ↓
release ID、commit 和 archive URL
    ↓
archive size、SHA-256 和 component hashes
```

任一步失败时，updater 保留当前版本。

## 版本顺序

| buildNumber | clientVersion |
| ---: | --- |
| 19 | `0.0.1.9` |
| 20 | `0.0.2.0` |

版本段只有一位十进制数字。
因此 `0.0.1.10` 不是有效客户端版本。

## 生成

1. 构建并签名 app、helper 和 updater。
2. 创建 `CovioUpdate-<clientVersion>.zip`。
3. 运行 `scripts/update_manifest.py generate`。
4. 使用离线私钥和 `CovioUpdateSigner` 生成签名信封。
5. 上传 manifest、签名信封和 archive 到固定 internal Release。

生成命令：

```sh
python3 -I scripts/update_manifest.py generate \
  --release-manifest release/release-manifest.json \
  --archive build/dist/CovioUpdate-0.0.2.0.zip \
  --app-executable Covio.app/Contents/MacOS/Covio \
  --helper CovioHelper \
  --updater CovioUpdater \
  --commit <40 lowercase hex characters> \
  --key-id <key ID> \
  --signer build/update-signing/CovioUpdateSigner \
  --private-key <offline private key file> \
  --output-dir build/dist
```

私钥文件不得进入仓库、CI 缓存、Release 资产或普通用户目录。

## 验证入口

```sh
bash scripts/build-update-signature-tool.sh
python3 -I scripts/test_update_manifest.py
bash scripts/test-all.sh
```

Swift 侧验证入口是 `UpdateManifestVerifier`。XCTest 覆盖签名、摘要、渠道、版本、协议、URL 和最低系统版本。
