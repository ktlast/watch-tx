# watch-tx
在 terminal 用 shell script 持續觀察台指期報價，方便看盤

<br>

## 支援 OS
- 目前只支援 `MacOS` 和 `Linux`

<br>

## 需要安裝的套件

- `jq`

### Linux

```bash
sudo apt-get install jq
```

<br>

### MacOS

```bash
brew install jq
```

<br>

## 使用方法

```bash
curl -s https://raw.githubusercontent.com/ktlast/watch-tx/master/watch_tx.sh | bash
```

<br>

## Example Output

```bash
臺指期015 (regular)

date             Futures               | Actuals               trash

[12/27 10:51:31] 23333 +7 (185, 32)    | 23282 +36 (78, 53)    ==> CPU usage: 8.7% user, 13.65% sys, 78.26% idle
[12/27 10:51:35] 23333 +7 (185, 32)    | 23282 +36 (78, 53)    ==> CPU usage: 7.60% user, 13.18% sys, 79.21% idle
```

Note

- 小括號內的數字，左邊為現價與最低價的差距，右邊為最高價與現價的差距。

  所以

  ```bash
   # 破底時，會看到
   (0, X)

   # 突破前高時
   (X, 0)
   ```