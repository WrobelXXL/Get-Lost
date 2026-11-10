FROM mcr.microsoft.com/powershell:7.4-alpine-3.20

WORKDIR /app
COPY app/maze-gen/main.ps1 app/maze-gen/config.yml app/maze-gen/player-control.ps1 ./

CMD ["pwsh", "-NoProfile", "-File", "main.ps1"]
