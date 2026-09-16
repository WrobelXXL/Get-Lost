FROM mcr.microsoft.com/powershell:7.4-alpine-3.20

WORKDIR /app
COPY app/maze-gen/main.ps1 app/maze-gen/config.yml ./

CMD ["pwsh", "-NoProfile", "-File", "main.ps1"]
