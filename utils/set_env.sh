# #!/bin/bash
# set -e

# ------------------------------Mac上安装Homebrew------------------------------------------

echo ">>> 安装 Homebrew..."
/bin/zsh -c "$(curl -fsSL https://gitee.com/cunkai/HomebrewCN/raw/master/Homebrew.sh)"

echo ">>> 更新并升级 Homebrew..."
brew update && brew upgrade

echo ">>> 安装常用工具..."
brew install git vim wget curl tree htop tmux nmap iperf3 

echo ">>> 安装 Docker..."
brew install --cask docker

echo ">>> 所有工具安装完成！"


# ------------------------------zsh 插件------------------------------------------
## 安装 zsh 与 oh-my-zsh & oh-my-zsh 插件
echo ">>> 安装 oh-my-zsh..."
sh -c "$(curl -fsSL https://gitee.com/pocmon/ohmyzsh/raw/master/tools/install.sh)" || true

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
git clone https://gitee.com/hailin_cool/zsh-autosuggestions.git "$ZSH_CUSTOM/plugins/zsh-autosuggestions" || true
git clone https://gh.xmly.dev/https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" || true
echo "zsh 插件安装完成."

### 修改 ~/.zshrc 插件列表
echo ">>> 修改 ~/.zshrc 中的插件配置..."
if grep -q "plugins=(git)" "$HOME/.zshrc"; then
    # macOS 需要为 -i 选项指定备份文件扩展名
    sed -i '' 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$HOME/.zshrc"
    echo "~/.zshrc 插件配置已更新。"
else
    echo "未在 ~/.zshrc 中找到 'plugins=(git)' 字样，请手动检查配置。"
fi
# 使配置生效
if [ -n "$ZSH_VERSION" ]; then
    source "$HOME/.zshrc"
fi

# --------------设置开发环境：python3.10、pip源--------------------
## 安装指定版本python
#!/bin/bash
set -e

### 使用 Homebrew 安装 Python 3.10
echo ">>> 安装 Python 3.10..."
brew install python@3.10

#### 检查 Python 3.10 是否安装成功
if [ -x "/opt/homebrew/bin/python3.10" ]; then
    echo "Python 3.10 安装成功！"
else
    echo "Python 3.10 安装失败，请检查 Homebrew 安装日志。" >&2
    exit 1
fi

source ~/.zshrc

### 更新 pip 并设置 pip 源为清华镜像
echo ">>> 升级 pip 并设置 pip 源为清华镜像..."
python -m pip install --upgrade pip
pip config set global.index-url https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple
pip install virtualenv

# ------------------------------配置SSH密钥------------------------------------------
## 生成 SSH 密钥（如果尚未存在）
SSH_KEY="$HOME/.ssh/id_rsa"
if [ -f "$SSH_KEY" ]; then
    echo "SSH 密钥已存在，跳过生成。"
else
    echo ">>> 生成新的 SSH 密钥..."
    ssh-keygen -t rsa -b 4096 -C "ai_diagnosis@126.com" -f "$SSH_KEY" -N ""
    if [ $? -eq 0 ]; then
        echo "SSH 密钥生成成功：$SSH_KEY"
    else
        echo "SSH 密钥生成失败，请检查错误信息。" >&2
        exit 1
    fi
fi