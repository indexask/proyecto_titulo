-- ============================================================================
-- GyGTrack — Peajes interurbanos de los accesos a Santiago (RF-24).
-- GENERADO por supabase/datos/tag/generar_porticos.mjs — no editar a mano.
--
-- Ubicación y sentido: © colaboradores de OpenStreetMap (ODbL), nodos
--   toll_booth/toll_gantry y su calzada (rumbo null = cobra en ambos sentidos).
-- Tarifas: MOP / Dirección General de Concesiones, Peajes Tarifas 2026 (con
--   TAG): Autopista Los Libertadores, Ruta 68, Ruta 78, Ruta 5 Sur
--   (Santiago - Talca) y Ruta 5 Norte (Santiago - Los Vilos). Los horarios
--   punta que los PDF no definen se estiman con la tarifa normal [VALIDAR].
-- ============================================================================

insert into public.portico (osm_id, concesion, codigo, tramo, lat, lng, rumbo, km, por_km, tarifas, horario) values
  (243646585, 'Ruta 68', 'Lo Prado', 'Troncal Lo Prado', -33.456415, -70.8986965, 252.4, 0, false, '{"1":{"tbfp":2700,"tbp":4000},"2":{"tbfp":4800,"tbp":7200}}'::jsonb, '{}'::jsonb),
  (267454369, 'Autopista Los Libertadores', 'Las Canteras', 'Plaza Las Canteras', -33.3108701, -70.7021396, 29, 0, false, '{"1":{"tbfp":1400},"2":{"tbfp":2500}}'::jsonb, '{}'::jsonb),
  (276093010, 'Ruta 68', 'Troncal Sur', 'Troncal Sur', -33.0629256, -71.4340409, 277, 0, false, '{"1":{"tbfp":1100},"2":{"tbfp":1900}}'::jsonb, '{}'::jsonb),
  (277060427, 'Autopista Los Libertadores', 'Las Canteras', 'Plaza Las Canteras', -33.3107111, -70.7024802, 209.7, 0, false, '{"1":{"tbfp":1400},"2":{"tbfp":2500}}'::jsonb, '{}'::jsonb),
  (289394039, 'Ruta 5 Norte (Santiago - Los Vilos)', 'Túnel El Melón', 'Túnel El Melón', -32.629614, -71.2308575, 189.2, 0, false, '{"1":{"tbfp":2900},"2":{"tbfp":5300}}'::jsonb, '{}'::jsonb),
  (294489553, 'Ruta 68', 'Troncal Sur', 'Troncal Sur', -33.063448, -71.4341262, 97.5, 0, false, '{"1":{"tbfp":1100},"2":{"tbfp":1900}}'::jsonb, '{}'::jsonb),
  (314200644, 'Autopista Los Libertadores', 'San José', 'Plaza San José', -33.2700796, -70.7354601, null, 0, false, '{"1":{"tbfp":1400},"2":{"tbfp":2500}}'::jsonb, '{}'::jsonb),
  (335639289, 'Autopista Los Libertadores', 'Chacabuco', 'Plaza Chacabuco', -33.0007885, -70.6872448, null, 0, false, '{"1":{"tbfp":3300},"2":{"tbfp":6000}}'::jsonb, '{}'::jsonb),
  (454636152, 'Ruta 78', 'T1', 'Américo Vespucio', -33.4848651, -70.7410211, 70.6, 0, false, '{"1":{"tbfp":718,"tbp":1077},"2":{"tbfp":1436,"tbp":2872}}'::jsonb, '{}'::jsonb),
  (454636182, 'Ruta 78', 'T1', 'Américo Vespucio', -33.4847582, -70.741127, 249.9, 0, false, '{"1":{"tbfp":718,"tbp":1077},"2":{"tbfp":1436,"tbp":2872}}'::jsonb, '{}'::jsonb),
  (1502159436, 'Ruta 5 Norte (Santiago - Los Vilos)', 'Pichidangui', 'Plaza Pichidangui', -32.1749622, -71.5206745, 14, 0, false, '{"1":{"tbfp":2900},"2":{"tbfp":5300}}'::jsonb, '{}'::jsonb),
  (1502159456, 'Ruta 5 Norte (Santiago - Los Vilos)', 'Pichidangui', 'Plaza Pichidangui', -32.1748955, -71.5210594, 195.5, 0, false, '{"1":{"tbfp":2900},"2":{"tbfp":5300}}'::jsonb, '{}'::jsonb),
  (1946795899, 'Ruta 5 Norte (Santiago - Los Vilos)', 'Lampa', 'Plaza Lampa', -33.2357344, -70.7592174, 159.2, 0, false, '{"1":{"tbfp":900},"2":{"tbfp":1600}}'::jsonb, '{}'::jsonb),
  (1946795918, 'Ruta 5 Norte (Santiago - Los Vilos)', 'Lampa', 'Plaza Lampa', -33.2355669, -70.7586049, 339.2, 0, false, '{"1":{"tbfp":900},"2":{"tbfp":1600}}'::jsonb, '{}'::jsonb),
  (4249905414, 'Ruta 5 Sur (Santiago - Talca)', 'Angostura', 'Troncal Ruta 5 (Angostura)', -33.9078062, -70.7314403, 137.6, 0, false, '{"1":{"tbfp":3800},"2":{"tbfp":6900}}'::jsonb, '{}'::jsonb),
  (4503134946, 'Ruta 5 Sur (Santiago - Talca)', 'Angostura', 'Troncal Ruta 5 (Angostura)', -33.9074017, -70.7309078, 316.8, 0, false, '{"1":{"tbfp":3800},"2":{"tbfp":6900}}'::jsonb, '{}'::jsonb),
  (5508725661, 'Ruta 68', 'Lo Prado', 'Troncal Lo Prado', -33.4573556, -70.8983566, 72.2, 0, false, '{"1":{"tbfp":2700,"tbp":4000},"2":{"tbfp":4800,"tbp":7200}}'::jsonb, '{}'::jsonb),
  (5516568781, 'Ruta 5 Sur (Santiago - Talca)', 'Tocornal', 'Troncal Tocornal', -33.6050323, -70.6046629, 173.5, 0, false, '{"1":{"tbfp":207},"2":{"tbfp":372}}'::jsonb, '{}'::jsonb),
  (5532689550, 'Ruta 78', 'T3', 'Padre Hurtado', -33.5528306, -70.8139017, 241.7, 0, false, '{"1":{"tbfp":225,"tbp":337.5},"2":{"tbfp":450,"tbp":900}}'::jsonb, '{}'::jsonb),
  (6122216578, 'Ruta 5 Norte (Santiago - Los Vilos)', 'Buenaventura', 'Enlace Buenaventura', -33.3398283, -70.7120052, 339.5, 0, false, '{"1":{"tbfp":218,"tbp":436},"2":{"tbfp":392,"tbp":785}}'::jsonb, '{}'::jsonb),
  (6479098231, 'Ruta 5 Sur (Santiago - Talca)', 'Gabriela', 'Troncal Gabriela', -33.5819958, -70.6112359, 177.6, 0, false, '{"1":{"tbfp":621},"2":{"tbfp":1117}}'::jsonb, '{}'::jsonb),
  (6479098244, 'Ruta 5 Sur (Santiago - Talca)', 'Gabriela', 'Troncal Gabriela', -33.5816991, -70.6102952, 332.5, 0, false, '{"1":{"tbfp":621},"2":{"tbfp":1117}}'::jsonb, '{}'::jsonb),
  (6518635362, 'Ruta 5 Sur (Santiago - Talca)', 'Tocornal', 'Troncal Tocornal', -33.6047726, -70.6038751, 339, 0, false, '{"1":{"tbfp":207},"2":{"tbfp":372}}'::jsonb, '{}'::jsonb),
  (6548809057, 'Ruta 5 Norte (Santiago - Los Vilos)', 'Buenaventura', 'Enlace Buenaventura', -33.3398151, -70.7122122, 159.5, 0, false, '{"1":{"tbfp":218,"tbp":436},"2":{"tbfp":392,"tbp":785}}'::jsonb, '{}'::jsonb),
  (6548823501, 'Ruta 5 Norte (Santiago - Los Vilos)', 'Lo Marcoleta', 'Paso Superior Lo Marcoleta', -33.357992, -70.7040905, 159.3, 0, false, '{"1":{"tbfp":181,"tbp":362},"2":{"tbfp":326,"tbp":652}}'::jsonb, '{}'::jsonb),
  (6548823505, 'Ruta 5 Norte (Santiago - Los Vilos)', 'Lo Marcoleta', 'Paso Superior Lo Marcoleta', -33.3580071, -70.7038343, 339.5, 0, false, '{"1":{"tbfp":181,"tbp":362},"2":{"tbfp":326,"tbp":652}}'::jsonb, '{}'::jsonb),
  (6613063427, 'Ruta 68', 'Zapata', 'Troncal Zapata', -33.3715517, -71.3000625, 118.8, 0, false, '{"1":{"tbfp":2700,"tbp":4000},"2":{"tbfp":4800,"tbp":7200}}'::jsonb, '{}'::jsonb),
  (6613063432, 'Ruta 68', 'Zapata', 'Troncal Zapata', -33.3706472, -71.2994676, 298.7, 0, false, '{"1":{"tbfp":2700,"tbp":4000},"2":{"tbfp":4800,"tbp":7200}}'::jsonb, '{}'::jsonb),
  (6615396115, 'Ruta 5 Norte (Santiago - Los Vilos)', 'Lo Pinto', 'Enlace Lo Pinto', -33.2799197, -70.7390951, 159.4, 0, false, '{"1":{"tbfp":486,"tbp":972},"2":{"tbfp":875,"tbp":1750}}'::jsonb, '{}'::jsonb),
  (6615396116, 'Ruta 5 Norte (Santiago - Los Vilos)', 'Lo Pinto', 'Enlace Lo Pinto', -33.2799505, -70.7388797, 339.4, 0, false, '{"1":{"tbfp":486,"tbp":972},"2":{"tbfp":875,"tbp":1750}}'::jsonb, '{}'::jsonb),
  (6615396126, 'Ruta 5 Norte (Santiago - Los Vilos)', 'La Montaña', 'Paso Superior La Montaña', -33.3170776, -70.7224191, 159.5, 0, false, '{"1":{"tbfp":397,"tbp":794},"2":{"tbfp":715,"tbp":1429}}'::jsonb, '{}'::jsonb),
  (6615396127, 'Ruta 5 Norte (Santiago - Los Vilos)', 'La Montaña', 'Paso Superior La Montaña', -33.31711, -70.7222014, 339.4, 0, false, '{"1":{"tbfp":397,"tbp":794},"2":{"tbfp":715,"tbp":1429}}'::jsonb, '{}'::jsonb),
  (9008699779, 'Ruta 78', 'T8', 'Pomaire/Melipilla', -33.6693012, -71.1507237, 266, 0, false, '{"1":{"tbfp":599,"tbp":898.5},"2":{"tbfp":1198,"tbp":2396}}'::jsonb, '{}'::jsonb),
  (12511401244, 'Ruta 78', 'T6', 'Talagante', -33.6429011, -70.8756342, 211.7, 0, false, '{"1":{"tbfp":375,"tbp":562.5},"2":{"tbfp":750,"tbp":1500}}'::jsonb, '{}'::jsonb),
  (12511401245, 'Ruta 78', 'T6', 'Talagante', -33.6429391, -70.8754904, 31.5, 0, false, '{"1":{"tbfp":375,"tbp":562.5},"2":{"tbfp":750,"tbp":1500}}'::jsonb, '{}'::jsonb),
  (12511401260, 'Ruta 78', 'T2', 'Rinconada', -33.4956473, -70.7771624, 75.3, 0, false, '{"1":{"tbfp":330,"tbp":495},"2":{"tbfp":660,"tbp":1320}}'::jsonb, '{}'::jsonb),
  (12511401261, 'Ruta 78', 'T2', 'Rinconada', -33.4955303, -70.777166, 255.6, 0, false, '{"1":{"tbfp":330,"tbp":495},"2":{"tbfp":660,"tbp":1320}}'::jsonb, '{}'::jsonb),
  (12511401267, 'Ruta 78', 'T3', 'Padre Hurtado', -33.5529192, -70.8137842, 61.6, 0, false, '{"1":{"tbfp":225,"tbp":337.5},"2":{"tbfp":450,"tbp":900}}'::jsonb, '{}'::jsonb),
  (12511401272, 'Ruta 78', 'T4', 'Malloco', -33.5878075, -70.8450495, 174.4, 0, false, '{"1":{"tbfp":225,"tbp":337.5},"2":{"tbfp":450,"tbp":900}}'::jsonb, '{}'::jsonb),
  (12511401277, 'Ruta 78', 'T4', 'Malloco', -33.6012541, -70.8471047, 25.5, 0, false, '{"1":{"tbfp":225,"tbp":337.5},"2":{"tbfp":450,"tbp":900}}'::jsonb, '{}'::jsonb),
  (12511401282, 'Ruta 78', 'T7', 'El Paico', -33.6848212, -70.943167, 56.2, 0, false, '{"1":{"tbfp":375,"tbp":562.5},"2":{"tbfp":750,"tbp":1500}}'::jsonb, '{}'::jsonb),
  (12511401283, 'Ruta 78', 'T7', 'El Paico', -33.6846963, -70.943213, 236.2, 0, false, '{"1":{"tbfp":375,"tbp":562.5},"2":{"tbfp":750,"tbp":1500}}'::jsonb, '{}'::jsonb),
  (12511401284, 'Ruta 78', 'T8', 'Pomaire/Melipilla', -33.6694249, -71.1507469, 86.2, 0, false, '{"1":{"tbfp":599,"tbp":898.5},"2":{"tbfp":1198,"tbp":2396}}'::jsonb, '{}'::jsonb),
  (12511410970, 'Ruta 78', 'T10', 'Puangue', -33.6474761, -71.3601781, 312.4, 0, false, '{"1":{"tbfp":1161,"tbp":1741.5},"2":{"tbfp":2322,"tbp":4644}}'::jsonb, '{}'::jsonb),
  (12511410971, 'Ruta 78', 'T10', 'Puangue', -33.647546, -71.3602912, 132.5, 0, false, '{"1":{"tbfp":1161,"tbp":1741.5},"2":{"tbfp":2322,"tbp":4644}}'::jsonb, '{}'::jsonb),
  (13743054369, 'Ruta 5 Sur (Santiago - Talca)', 'Río Maipo', 'Troncal Río Maipo', -33.6625108, -70.6678914, 235.8, 0, false, '{"1":{"tbfp":621},"2":{"tbfp":1117}}'::jsonb, '{}'::jsonb),
  (13743054399, 'Ruta 5 Sur (Santiago - Talca)', 'Río Maipo', 'Troncal Río Maipo', -33.6627807, -70.6680037, 55.2, 0, false, '{"1":{"tbfp":621},"2":{"tbfp":1117}}'::jsonb, '{}'::jsonb)
on conflict (osm_id) do nothing;
