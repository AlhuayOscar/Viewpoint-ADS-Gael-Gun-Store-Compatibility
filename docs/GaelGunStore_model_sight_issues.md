# GaelGunStore: errores de mira y modelo

Checklist de revisión visual. Los números entre paréntesis corresponden al catálogo del calibrador de ViewpointGaelCompat. Esta lista no modifica los perfiles ADS.

| # | Arma | ID | Área a revisar | Observación | Estado |
|---:|---|---|---|---|---|
| 1 | Deagle .50 AE | `Base.Deagle50AE` (#9) | Mira / modelo | Error reportado; falta precisar qué parte del modelo o de la mira falla. | [ ] Pendiente |
| 2 | Glock 43 | `Base.Glock43` (#18) | Mira / modelo | Error reportado; falta precisar qué parte del modelo o de la mira falla. | [ ] Pendiente |
| 3 | GSH-18 | `Base.GSH18` (#21) | Modelo visual | Se ve mal; la mira no es el problema. | [ ] Pendiente |
| 4 | SIG P228 | `Base.P228` (#32) | Modelo visual | Error visual. | [ ] Pendiente |
| 5 | Beretta M9 vanilla | `Base.Pistol` (#35) | Modelo visual | Revisar el aspecto del modelo de la pistola vanilla. | [ ] Pendiente |
| 6 | Pistol Shotgun | `Base.pistol_shotgun` (#38) | Miras de hierro | No se ve mira trasera ni delantera centrada; comprobar si el diseño es intencional. | [ ] Pendiente |
| 7 | Samurai Albert Wesker | `Base.Samurai_aw` (#39) | Modelo visual | Error visual. | [ ] Pendiente |
| 8 | Wildey | `Base.Wildey` (#46) | Miras de hierro | Revisar la geometría o ubicación de las miras. | [ ] Pendiente |
| 9 | Colt Navy 1851 | `Base.ColtNavy1851` (#49) | Miras de hierro | Revisar la geometría o ubicación de las miras. | [ ] Pendiente |

Para cada caso: confirmar el defecto con el arma sin óptica, inspeccionar el modelo y sus puntos de mira, corregir el recurso 3D o sus anexos si corresponde y volver a comprobar ADS. Mantener las calibraciones manuales existentes hasta verificar la corrección visual en juego.
