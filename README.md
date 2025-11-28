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
-v ./service_data/logs:/app/logs \
-v ./service_conf/ai_diagnosis/models:/app/models \
-v ./service_conf/ai_diagnosis/conf:/app/conf \
-p 7860:7860  \
--name ai-diagnosis-service \
ai-diagnosis-service:v1.0.0

# 启动数据处理服务
cd ~/projects/chifeng-ai-diagnosis

docker run -d -p 8501:8501 \
  -v ./service_conf/parse_data/conf:/app/conf \
  --name parse-data-service \
  parse-data-service:v1.0.0

# 服务监控软件


# 编写定时任务，做数据备份，且只保留最近180天的数据备份

# 
