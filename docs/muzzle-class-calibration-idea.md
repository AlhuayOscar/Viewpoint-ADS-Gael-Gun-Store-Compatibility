# Idea: calibración aproximada del origen del muzzle por clase

Propuesta para retomar después de la restauración de la calibración experimental de `Muzzle X`:

- Usar como referencia horizontal el centro de la cámara o de la cabeza del personaje.
- Desplazar el origen de disparo hacia delante según el largo del arma, con un valor fijo o promedio por clasificación (pistola, SMG, rifle, escopeta, etc.). No hace falta que coincida exactamente con la boca del cañón.
- Aplicar también una corrección vertical pequeña, basada en la altura promedio del eje de los barriles para esa clase.
- Mantenerlo como aproximación configurable por clase; luego ajustar manualmente las armas atípicas.

Al implementarlo, verificar por separado el punto visual del muzzle y el origen que usa la simulación balística: mover uno no garantiza que el otro cambie. Probar en juego con el marcador de calibración y confirmar que los disparos reales sigan ese origen.
