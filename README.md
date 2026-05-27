# AI Interviewer - LLM Deployment Pipeline

Dự án tập trung vào việc đóng gói và triển khai tự động ứng dụng phỏng vấn thông minh (sử dụng LangChain, FAISS, MongoDB ) lên hệ thống máy chủ vật lý hoặc cloud thông qua Docker và GitHub Actions.
<img width="1640" height="870" alt="demo" src="https://github.com/user-attachments/assets/64152774-a191-4453-95d6-570995b8b140" />

# Quick Start

**1. Tạo file biến môi trường (`.env`):**
Tạo file `.env` tại thư mục gốc của dự án và điền các khóa API:
```text
GOOGLE_API_KEY="paste_your_api_key_here"
GOOGLE_API_KEY1="paste_your_api_key_here"
# ... các biến khác
```

**2. Tạo file xác thực Google (`credentials.json`):**
Tạo file `credentials.json` tại thư mục gốc với cấu trúc:
```json
{
  "web": {
    "client_id": "",
    "project_id": "",
    "auth_uri": "",
    "token_uri": "",
    "auth_provider_x509_cert_url": "",
    "client_secret": "",
    "redirect_uris": [],
    "javascript_origins": []
  }
}
```

**3. Kéo Image và Khởi chạy:**
Thực thi các lệnh sau để kéo Image đã đóng gói sẵn từ Registry và khởi chạy dịch vụ:
```bash
# Kéo image mới nhất từ Github Container Registry
docker pull ghcr.io/huynongquoc05/deployllm_interviewer:latest 

# Khởi chạy hệ thống, giới hạn tự động build và mở rộng 2 replica cho ứng dụng web
docker compose up -d --scale web=2 --no-build
```

**4. Kiểm tra:**
Truy cập ứng dụng tại địa chỉ `http://<IP_SERVER>:8005` hoặc `http://localhost:8005` (nếu chạy trên máy cá nhân).


## 1. Kiến trúc Đóng gói (Dockerization)

Ứng dụng được thiết kế theo mô hình Microservices, quản lý tập trung bởi Docker Compose.

### Dockerfile

* **Cấu trúc:** Sử dụng Multi-stage Build phân chia rõ hai giai đoạn (`builder` và `runtime`).

* **Môi trường:** Kế thừa từ Base Image `python:3.12-slim`. Các thư viện học sâu (như PyTorch) được cấu hình cài đặt phiên bản CPU-only, giúp tối ưu dung lượng Image .

* **Quản lý cấu hình:** Các tệp tin chứa thông tin xác thực và biến môi trường (`.env`, `credentials.json`) được loại trừ hoàn toàn khỏi quá trình build thông qua `.dockerignore`.

### Docker Compose & Network Flow


```yaml
services:
  web:
    build: .
    image: ghcr.io/huynongquoc05/deployllm_interviewer:latest
    environment:
      MONGO_URI: mongodb://host.docker.internal:27017/
    env_file:
      - .env
    volumes:
      - ./credentials.json:/app/credentials.json

  nginx:
    image: nginx:latest
    ports:
      - "8005:80"
    volumes:
      - ./Nginx.conf:/etc/nginx/conf.d/default.conf
    depends_on:
      - web
```

* **Dịch vụ Web (Flask):** Quản lý ứng dụng lõi, đọc cấu hình qua biến môi trường và tệp `.env`. Cấp quyền truy cập tệp `credentials.json` thông qua Bind Mount.

* **Dịch vụ Proxy (Nginx):** Đóng vai trò Reverse Proxy, tiếp nhận yêu cầu từ cổng `8005` của host và điều hướng vào cổng `80` nội bộ.

* **Kết nối với MongoDB bên ngoài:** Ứng dụng kết nối tới MongoDB cài đặt trực tiếp trên máy chủ thông qua cầu nối `host.docker.internal`.


## 2. Quy trình CI/CD (GitHub Actions)

Hệ thống cấu hình GitHub Actions để thiết lập đường ống (Pipeline) tự động hóa từ bước kiểm tra mã nguồn đến triển khai thực tế.
<img width="1423" height="293" alt="pipeline" src="https://github.com/user-attachments/assets/2f6caca1-43cd-441a-a82c-0b7b254f370e" />


### Các giai đoạn (Jobs):

#### Job 1: Check_code (Linting)

Chạy `flake8` để kiểm tra lỗi cú pháp và chuẩn trình bày mã nguồn Python.

```yaml
  Check_code:
    runs-on: ubuntu-latest
    steps:
      - name: Kéo mã nguồn về máy chủ
        uses: actions/checkout@v4
      - name: Thiết lập Python 3.12
        uses: actions/setup-python@v5
        with:
          python-version: 3.12
          cache: 'pip'
      - name: cài flake8
        run: pip install flake8
      - name: Quét mã nguồn bằng Flake8
        run: flake8 . --count --select=E9,F63,F7,F82 --show-source --statistics
```

#### Job 2: Build_test_and_push_image

 
```yaml
  build_test_and_push_image:
    needs: Check_code
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - name: Kéo mã nguồn về máy chủ
        uses: actions/checkout@v4
      - name: Giải mã file bảo mật từ Base64
        run: |
            echo "${{ secrets.ENV_B64 }}" | base64 --decode > .env
            echo "${{ secrets.CREDENTIALS_B64 }}" | base64 --decode > credentials.json
      - name: Build và khởi chạy hệ thống bằng Docker Compose
        run: docker compose up --build -d --scale web=2
      - name: Chờ hệ thống khởi động (30 giây)
        run: sleep 30
      - name: Kiểm tra kết nối Web (Ping thử Nginx)
        run: curl -f http://localhost:8005 || exit 1
      - name: Đăng nhập vào GitHub Container Registry
        uses: docker/login-action@v4
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: push image
        run: docker push ghcr.io/huynongquoc05/deployllm_interviewer:latest
      - name: Dọn dẹp (Tắt container)
        run: docker compose down
```

#### Job 3: Deploy

Kết nối SSH tới Server vật lý, đồng bộ tệp cấu hình mới và tải Image từ Registry về để khởi chạy dịch vụ với tham số `--no-build`.

```yaml
  deploy:
    needs: build_test_and_push_image
    runs-on: ubuntu-latest
    steps:
      - name: Kết nối ssh đến sver
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ${{ secrets.SERVER_USERNAME }}
          key: ${{ secrets.SERVER_SSH_KEY }}
          port: 8901
          script: |
            cd /home/huynq/DeployLLM_Interviewer
            git pull origin main
            docker compose down
            docker pull ghcr.io/huynongquoc05/deployllm_interviewer:latest 
            docker compose up -d --scale web=2 --no-build
            sleep 50
            curl -f http://localhost:8005 || exit 1
```

## 3. Hướng dẫn chạy

### A. Triển khai tự động (CI/CD)

1. **Chuẩn bị Secrets:** Cấu hình các biến `ENV_B64`, `CREDENTIALS_B64`, `SERVER_HOST`, `SERVER_SSH_KEY` trong GitHub Repository.
2. **Khởi chạy:** Mọi thao tác `git push` lên nhánh `main` hoặc `master` sẽ tự động kích hoạt toàn bộ quy trình trên.
```yaml
on:
  push:
    branches:
      ["main", "master"]
  pull_request:
    branches:
      ["main", "master"]
```

# Quick Start

**1. Tạo file biến môi trường (`.env`):**
Tạo file `.env` tại thư mục gốc của dự án và điền các khóa API:
```text
GOOGLE_API_KEY="paste_your_api_key_here"
GOOGLE_API_KEY1="paste_your_api_key_here"
# ... các biến khác
```

**2. Tạo file xác thực Google (`credentials.json`):**
Tạo file `credentials.json` tại thư mục gốc với cấu trúc:
```json
{
  "web": {
    "client_id": "",
    "project_id": "",
    "auth_uri": "",
    "token_uri": "",
    "auth_provider_x509_cert_url": "",
    "client_secret": "",
    "redirect_uris": [],
    "javascript_origins": []
  }
}
```

**3. Kéo Image và Khởi chạy:**
Thực thi các lệnh sau để kéo Image đã đóng gói sẵn từ Registry và khởi chạy dịch vụ:
```bash
# Kéo image mới nhất từ Github Container Registry
docker pull ghcr.io/huynongquoc05/deployllm_interviewer:latest 

# Khởi chạy hệ thống, giới hạn tự động build và mở rộng 2 replica cho ứng dụng web
docker compose up -d --scale web=2 --no-build
```

**4. Kiểm tra:**
Truy cập ứng dụng tại địa chỉ `http://<IP_SERVER>:8005` hoặc `http://localhost:8005` (nếu chạy trên máy cá nhân).
