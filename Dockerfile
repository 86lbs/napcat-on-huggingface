FROM mlikiowa/napcat-docker:base
RUN apt-get update && apt-get install -y xvfb unzip curl nginx python3 python3-pip zip git && \
    pip3 install --no-cache-dir huggingface_hub websockets && \
    rm -rf /var/lib/apt/lists/*
RUN useradd -m -u 1000 user
WORKDIR /app
RUN curl -L -o NapCat.Shell.zip https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip && \
    unzip -q NapCat.Shell.zip -d ./napcat && \
    rm NapCat.Shell.zip
RUN arch=$(arch | sed s/aarch64/arm64/ | sed s/x86_64/amd64/) && \
    curl -o linuxqq.deb https://dldir1v6.qq.com/qqfile/qq/QQNT/7516007c/linuxqq_3.2.25-45758_${arch}.deb && \
    apt-get update && \
    apt-get install -y ./linuxqq.deb && \
    rm linuxqq.deb && \
    rm -rf /var/lib/apt/lists/*
RUN echo "(async () => {await import('file:///app/napcat/napcat.mjs');})();" > /opt/QQ/resources/app/loadNapCat.js && \
    sed -i 's|"main": "[^"]*"|"main": "./loadNapCat.js"|' /opt/QQ/resources/app/package.json
COPY --chown=user:user entrypoint.sh /app/
COPY nginx.conf /etc/nginx/nginx.conf
RUN chmod +x /app/entrypoint.sh && \
    mkdir -p /app/napcat/config /app/.config/QQ /var/log/nginx /var/lib/nginx && \
    chown -R user:user /app /etc/nginx /var/log/nginx /var/lib/nginx
ENV DISPLAY=:99
ENV NAPCAT_DISABLE_MULTI_PROCESS=1
USER user
ENTRYPOINT ["/bin/bash", "/app/entrypoint.sh"]
