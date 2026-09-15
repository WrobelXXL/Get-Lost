# Get-Lost - Map-/Labyrinth-Generierung
#
# Erzeugt beim Start einmalig eine zufaellige Karte und legt sie im
# gemeinsamen Volume ab (siehe docker-compose.yml), das der
# Browser-Container mitliest. Danach beendet sich der Container wieder -
# es ist kein dauerhaft laufender Dienst.

FROM mcr.microsoft.com/powershell:7.4-alpine-3.20

WORKDIR /app
COPY app/maze-gen/main.ps1 app/maze-gen/config.yml ./

CMD ["pwsh", "-NoProfile", "-File", "main.ps1"]
