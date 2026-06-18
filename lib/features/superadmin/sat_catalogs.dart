// Catálogos oficiales del SAT para CFDI 4.0
//
// Fuente: Anexo 20 de la Resolución Miscelánea Fiscal vigente.
// Catálogos completos en: https://www.sat.gob.mx/consultas/

class SatCatalogs {
  // ── c_RegimenFiscal ────────────────────────────────────────────────────────

  static const List<({String key, String label})> regimenesFiscales = [
    (key: '601', label: '601 – General de Ley Personas Morales'),
    (key: '603', label: '603 – Personas Morales con Fines no Lucrativos'),
    (key: '605', label: '605 – Sueldos y Salarios e Ingresos Asimilados'),
    (key: '606', label: '606 – Arrendamiento'),
    (key: '607', label: '607 – Régimen de Enajenación o Adquisición de Bienes'),
    (key: '608', label: '608 – Demás ingresos'),
    (key: '610', label: '610 – Residentes en el Extranjero sin Establecimiento Permanente'),
    (key: '611', label: '611 – Ingresos por Dividendos (socios y accionistas)'),
    (key: '612', label: '612 – Personas Físicas con Actividades Empresariales y Profesionales'),
    (key: '614', label: '614 – Ingresos por intereses'),
    (key: '615', label: '615 – Régimen de los ingresos por obtención de premios'),
    (key: '616', label: '616 – Sin obligaciones fiscales'),
    (key: '620', label: '620 – Sociedades Cooperativas de Producción'),
    (key: '621', label: '621 – Incorporación Fiscal'),
    (key: '622', label: '622 – Actividades Agrícolas, Ganaderas, Silvícolas y Pesqueras'),
    (key: '623', label: '623 – Opcional para Grupos de Sociedades'),
    (key: '624', label: '624 – Coordinados'),
    (key: '625', label: '625 – Régimen de Plataformas Tecnológicas'),
    (key: '626', label: '626 – Régimen Simplificado de Confianza (RESICO)'),
  ];

  // ── c_TipoDeComprobante ─────────────────────────────────────────────────────

  static const List<({String key, String label})> tiposComprobante = [
    (key: 'I', label: 'I – Ingreso'),
    (key: 'E', label: 'E – Egreso'),
    (key: 'T', label: 'T – Traslado'),
    (key: 'N', label: 'N – Nómina'),
    (key: 'P', label: 'P – Pago'),
  ];

  // ── c_UsoCFDI (relevantes para gimnasios) ───────────────────────────────────

  static const List<({String key, String label})> usosCFDI = [
    (key: 'G01', label: 'G01 – Adquisición de mercancias'),
    (key: 'G02', label: 'G02 – Devoluciones, descuentos o bonificaciones'),
    (key: 'G03', label: 'G03 – Gastos en general'),
    (key: 'I01', label: 'I01 – Construcciones'),
    (key: 'I02', label: 'I02 – Mobilario y equipo de oficina por inversiones'),
    (key: 'I04', label: 'I04 – Equipo de computo y accesorios'),
    (key: 'I06', label: 'I06 – Comunicaciones telefónicas'),
    (key: 'I08', label: 'I08 – Otra maquinaria y equipo'),
    (key: 'D09', label: 'D09 – Depósitos en cuentas para el ahorro, primas'),
    (key: 'S01', label: 'S01 – Sin efectos fiscales'),
    (key: 'CP01', label: 'CP01 – Pagos'),
    (key: 'CN01', label: 'CN01 – Nómina'),
  ];

  // ── c_ClaveProdServ (servicios relevantes para gimnasios) ──────────────────

  static const List<({String key, String label})> claveProdServ = [
    (key: '80111506', label: 'Servicios de gimnasio / acondicionamiento físico'),
    (key: '80141607', label: 'Servicios de entrenador personal'),
    (key: '80141700', label: 'Servicios de membresía o afiliación'),
    (key: '80141702', label: 'Servicios de membresía de club deportivo'),
    (key: '80161500', label: 'Servicios de administración de instalaciones deportivas'),
    (key: '80161505', label: 'Renta de instalaciones deportivas'),
    (key: '82111803', label: 'Servicios de facturación y cobranza'),
    (key: '84121800', label: 'Servicios de procesamiento de pagos / terminal punto de venta'),
    (key: '86101600', label: 'Capacitación en educación física y salud'),
    (key: '86132000', label: 'Servicios de instructores deportivos'),
    (key: '90101801', label: 'Servicios de emisión de comprobantes fiscales digitales'),
    (key: '90111500', label: 'Desarrollo de software (SaaS)'),
    (key: '90111501', label: 'Suscripción a plataforma de software'),
    (key: '92101604', label: 'Servicios de promoción y publicidad'),
    (key: '93141706', label: 'Servicios de nutrición y dietética'),
    (key: '94132000', label: 'Alquiler de lockers y casilleros'),
    (key: '95121500', label: 'Venta de suplementos y artículos deportivos'),
    (key: '95121600', label: 'Venta de ropa y accesorios deportivos'),
    (key: '95121900', label: 'Venta de bebidas y alimentos preparados'),
    (key: '85122100', label: 'Servicios de fisioterapia y rehabilitación'),
    (key: '85101601', label: 'Servicios de evaluación física / check-up'),
    (key: '55111501', label: 'Licencia de uso de marca (franquicia gimnasio)'),
    (key: '80101501', label: 'Servicios de consultoría en gestión de gimnasios'),
    (key: '84121700', label: 'Servicios de inversión y financiamiento'),
  ];

  // ── c_ClaveUnidad ───────────────────────────────────────────────────────────

  static const List<({String key, String label})> claveUnidad = [
    (key: 'ACT', label: 'Actividad – Servicio'),
    (key: 'E48', label: 'Unidad de servicio'),
    (key: 'H87', label: 'Pieza'),
    (key: 'KGM', label: 'Kilogramo'),
    (key: 'LTR', label: 'Litro'),
    (key: 'MTR', label: 'Metro'),
    (key: 'MTK', label: 'Metro cuadrado'),
    (key: 'MON', label: 'Mes'),
    (key: 'DAY', label: 'Día'),
    (key: 'HUR', label: 'Hora'),
    (key: 'WEE', label: 'Semana'),
    (key: 'ANN', label: 'Año'),
    (key: 'C62', label: 'Unidad (concepto unitario)'),
    (key: 'XKI', label: 'Kit'),
    (key: 'SET', label: 'Conjunto / Set'),
    (key: 'PR', label: 'Par'),
    (key: 'EA', label: 'Elemento'),
    (key: 'AS', label: 'Variedad / Surtido'),
  ];

  // ── c_MetodoPago ────────────────────────────────────────────────────────────

  static const List<({String key, String label})> metodosPago = [
    (key: 'PUE', label: 'PUE – Pago en una sola exhibición'),
    (key: 'PPD', label: 'PPD – Pago en parcialidades o diferido'),
  ];

  // ── c_FormaPago ─────────────────────────────────────────────────────────────

  static const List<({String key, String label})> formasPago = [
    (key: '01', label: '01 – Efectivo'),
    (key: '02', label: '02 – Cheque nominativo'),
    (key: '03', label: '03 – Transferencia electrónica de fondos'),
    (key: '04', label: '04 – Tarjeta de crédito'),
    (key: '05', label: '05 – Monedero electrónico'),
    (key: '06', label: '06 – Dinero electrónico'),
    (key: '08', label: '08 – Vales de despensa'),
    (key: '12', label: '12 – Tarjeta de débito'),
    (key: '13', label: '13 – Tarjeta de servicio'),
    (key: '28', label: '28 – Tarjeta de débito (terminal punto de venta)'),
    (key: '29', label: '29 – Tarjeta de servicio (terminal punto de venta)'),
    (key: '99', label: '99 – Por definir'),
  ];

  // ── c_Moneda ────────────────────────────────────────────────────────────────

  static const List<({String key, String label})> monedas = [
    (key: 'MXN', label: 'MXN – Peso Mexicano'),
    (key: 'USD', label: 'USD – Dólar Americano'),
  ];

  // ── c_Periodicidad ──────────────────────────────────────────────────────────

  static const List<({String key, String label})> periodicidad = [
    (key: '01', label: '01 – Diario'),
    (key: '02', label: '02 – Semanal'),
    (key: '03', label: '03 – Catorcenal'),
    (key: '04', label: '04 – Quincenal'),
    (key: '05', label: '05 – Mensual'),
    (key: '06', label: '06 – Bimestral'),
    (key: '07', label: '07 – Trimestral'),
    (key: '08', label: '08 – Cuatrimestral'),
    (key: '10', label: '10 – Anual'),
    (key: '99', label: '99 – Otra periodicidad'),
  ];
}
