# zsx_waypoints-3D
---

## 📸 Preview

<div align="center">

<img src="preview/Preview1.png" width="48%">
<img src="preview/Preview2.png" width="48%">

</div>

---
## Uso

`ensure zsx_waypoints` no server.cfg. Marque um destino no mapa e entre em um
veículo terrestre. `/gps3d` abre o painel. ESC fecha. Configurações são salvas
localmente por jogador via KVP, inclusive após reconectar/reiniciar o recurso.

- Setas 3D acompanham a rota nativa e suas curvas.
- Cor, opacidade, distância entre setas, altura e tamanho ajustáveis ao vivo.
- Marcador flutuante com distância em metros/quilômetros.
- Sem rota válida, não inventa linhas retas atravessando prédios.
- Oculta durante pausa, seleção de personagem, telas com foco NUI e em aeronaves.
- Não cria veículos, NPCs, objetos persistentes ou tarefas de tráfego.
- `config.lua`: distâncias, limite de setas, intervalo e valores padrão.

## Integração

Exports de cliente:
```lua
exports.zsx_waypoints:OpenSettings()
exports.zsx_waypoints:SetDestination(vec3(2555.0, 329.0, 108.0), 'BASE PRF')
exports.zsx_waypoints:ClearDestination()
exports.zsx_waypoints:SetVisible(false) -- temporariamente ocultar
exports.zsx_waypoints:SetVisible(true)
```

SetDestination cria seu próprio blip roteado. ClearDestination só remove esse
blip; preserva o waypoint manual do jogador. A chegada limpa o destino criado
por export. O GPS manual continua sendo gerenciado pelo GTA.

O adaptador instalado em pickle_waypoints oculta somente o seu marcador manual
enquanto zsx_waypoints está iniciado. Marcadores administrativos são preservados.
`/waypointsettings` passa a abrir este painel. Ao parar o novo recurso, o marcador
manual original volta a funcionar.

## Validação em jogo

Testar destino novo, alteração/remoção de waypoint, curvas, túneis, pontes,
rodovias e chegada. Conferir se o azul, largura e altura correspondem à referência
na configuração gráfica utilizada. Abrir o painel, ajustar sliders e reiniciar
para conferir persistência. Testar também SetDestination/ClearDestination e pausa.

Natives usados: GET_POS_ALONG_GPS_TYPE_ROUTE (compatível com o alias antigo
GET_GPS_WAYPOINT_ROUTE_END), DRAW_POLY e projeção do destino na tela. A amostragem
consulta slot 0 para waypoint manual e slot 1 para o blip de destino exportado.
Referência: https://github.com/citizenfx/natives/blob/master/PATHFIND/GetPosAlongGpsTypeRoute.md
