# Alle Level aus config.yml generieren:
pwsh -NoProfile -File "app/maze-gen/main.ps1"

# Nur ein bestimmtes Level (z.B. Level 2):
pwsh -NoProfile -File "app/maze-gen/main.ps1" -Level 2

# Mit festem Seed (reproduzierbar):
pwsh -NoProfile -File "app/maze-gen/main.ps1" -Level 1 -Seed 42



docker compose run --rm maze-gen


docker compose run --rm maze-gen pwsh -NoProfile -File main.ps1 -Level 1
docker compose run --rm maze-gen pwsh -NoProfile -File main.ps1 -Level 2
docker compose run --rm maze-gen pwsh -NoProfile -File main.ps1 -Level 3