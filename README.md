# macos 相关账号
apple 账号：ai_diagnosis@126.com ChiFeng@123
126邮箱账号：ai_diagnosis@126.com ChiFeng@123

# 配置macos 系统环境(最好一步一步手动执行)
bash set_env.sh

# 构建镜像
# 新的 单独 dockerfile
rm -rf ktem_app_data logs venv # 删除旧数据
docker build -t ai-diagnosis-service:v1.0.0 -f Dockerfile.ai-diagnosis.v1.0.0 .


# 加载镜像
docker commit <容器ID或容器名> <新镜像名>:<tag>
docker save -o <保存路径/文件名.tar> <镜像名>:<tag>
docker load -i <文件名.tar>

docker save -o ai-diagnosis-service.v1.0.0.tar ai-diagnosis-service:v1.0.0
docker save -o parse-data-service.v1.0.0.tar parse-data-service:v1.0.0

docker load -i ai-diagnosis-service.v1.0.0.tar
docker load -i parse-data-service.v1.0.0.tar


# 启动ai辅助诊断服务
cd ~/projects/chifeng-ai-diagnosis

docker run -itd \
  -e GRADIO_SERVER_NAME=0.0.0.0 \
  -e GRADIO_SERVER_PORT=7860 \
  -v ./service_data/ktem_app_data:/app/ktem_app_data \
  -v ./service_data/ai_diagnosis_logs:/app/logs \
  -v ./service_conf/ai_diagnosis/models:/app/models \
  -v ./service_conf/ai_diagnosis/conf:/app/conf \
  -p 7860:7860  \
  --add-host=host.docker.internal:host-gateway \
  --name ai-diagnosis-service \
  ai-diagnosis-service:v1.0.0

# 启动数据处理服务
cd ~/projects/chifeng-ai-diagnosis

docker run -d -p 8501:8501 \
  -v ./service_conf/parse_data/conf:/app/conf \
  -v ./service_data/parse_data_logs:/app/logs \
  --add-host=host.docker.internal:host-gateway \
  --name parse-data-service \
  parse-data-service:v1.0.0

# 服务监控软件


# 编写定时任务，做数据备份，且只保留最近180天的数据备份

chmod +x ~/scripts/load_models.sh
crontab -e

0 * * * * /bin/bash /Users/ai_diagnosis/projects/chifeng-ai-diagnosis/utils/load_models.sh


crontab -l

# lms 加载模型 
命令	功能描述	适用场景
lms status	检查LM Studio运行状态	日常诊断、问题排查
lms server start	启动本地API服务器	开发集成、自动化脚本
lms server stop	停止本地API服务器	资源释放、环境清理
lms log stream	实时查看应用日志	调试模型加载、API调用
lms ls # 列出已下载模型（人类可读格式）
lms ls --json # 列出已下载模型（JSON格式，适合脚本处理）
lms load <模型路径> -y # 加载模型（最大GPU加速）
lms ps # 查看运行中模型
lms unload <模型标识符> # 卸载指定模型
lms unload --all # 卸载所有模型

lms load openai/gpt-oss-120b --context-length 60000 --identifier openai/gpt-oss-120b # 最大 131K
lms load openai/gpt-oss-20 --context-length 120000 --identifier openai/gpt-oss-20b # 最大 131K
lms load lm-kit/bge-m3-gguf/bge-m3-Q8_0.gguf --context-length 8192 --identifier text-embedding-bge-m3 # 8192 or 4096 

# 本项目 模型分布

1. ai_diagnosis 
  1. llm 模型 通过 kotaemon/flowsettings.py 配置
  2. embedding 模型 通过 kotaemon/flowsettings.py 配置
  3. rerank 模型 通过 ai_diagnosis/conf/rerank_models.json 配置；权重 chifeng-ai-diagnosis/service_conf/ai_diagnosis/models

2. parse_data
  1. llm 模型 chifeng-ai-diagnosis/service_conf/parse_data/conf/llm.json