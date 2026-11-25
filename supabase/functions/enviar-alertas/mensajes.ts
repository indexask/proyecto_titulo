// Contenido de las notificaciones push y destinatarios (RF-19). Sin
// dependencias, para poder probarlo de forma aislada (mensajes_test.ts).

export interface AlertaParaEnviar {
  tipo: "preventiva" | "dia_cero";
  cliente: string;
  numeroOc: string | null;
  fechaComprometida: string; // YYYY-MM-DD
}

function fechaChilena(iso: string): string {
  const [a, m, d] = iso.split("-");
  return `${d}-${m}-${a}`;
}

/** Título y cuerpo de la notificación. No incluye datos financieros. */
export function mensajeAlerta(a: AlertaParaEnviar): { titulo: string; cuerpo: string } {
  const pedido = a.numeroOc ? `${a.cliente} (OC ${a.numeroOc})` : a.cliente;
  if (a.tipo === "dia_cero") {
    return {
      titulo: "Día Cero: entrega vence HOY",
      cuerpo: `${pedido}: el plazo de entrega vence hoy (${fechaChilena(a.fechaComprometida)}).`,
    };
  }
  return {
    titulo: "Alerta preventiva de entrega",
    cuerpo: `${pedido}: el plazo de entrega vence el ${fechaChilena(a.fechaComprometida)}.`,
  };
}

/** Destinatarios: el responsable de la orden y todos los Administradores, sin repetir. */
export function destinatarios(responsableId: string | null, administradores: string[]): string[] {
  return [...new Set([...(responsableId ? [responsableId] : []), ...administradores])];
}
