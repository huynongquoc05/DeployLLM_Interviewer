FROM python:3.12-slim as builder

WORKDIR /app

# 1. Bổ sung các OS packages lõi cho AI/ML
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    g++ \
    make \
    python3-dev \
    libgomp1 \
    unixodbc-dev \
    curl \
    gnupg2 \
    && rm -rf /var/lib/apt/lists/* # Dọn rác apt ngay sau khi cài xong để giảm dung lượng

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .

# Tăng thời gian timeout cho pip vì tải PyTorch (từ sentence-transformers) rất lâu và nặng
RUN pip install --no-cache-dir --default-timeout=1000 \
    --extra-index-url https://download.pytorch.org/whl/cpu \
    -r requirements.txt

# 2. Tải sẵn dữ liệu NLTK ngay lúc build image (Tùy chọn nhưng RẤT khuyến khích)
# RUN python -m nltk.downloader punkt punkt_tab stopwords

FROM python:3.12-slim
WORKDIR /app

# Đã sửa lỗi chính tả buiqlder thành builder
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY . .

EXPOSE 8005

# Đã bỏ các dấu \ báo lỗi cú pháp trong mảng JSON
CMD ["gunicorn", "-b", "0.0.0.0:8005", "app:app", "-k", "gthread", "--threads", "4", "--timeout", "300", "--limit-request-field_size", "65536", "--limit-request-line", "65536", "--access-logfile", "-", "--error-logfile", "-", "--capture-output", "--enable-stdio-inheritance"]