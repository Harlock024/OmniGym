// Catálogos oficiales del SAT para CFDI 4.0

class SatCatalogs {
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

  static const List<({String key, String label})> tiposComprobante = [
    (key: 'I', label: 'I – Ingreso'),
    (key: 'E', label: 'E – Egreso'),
    (key: 'T', label: 'T – Traslado'),
    (key: 'N', label: 'N – Nómina'),
    (key: 'P', label: 'P – Pago'),
  ];

  // Catálogo c_UsoCFDI relevantes para gimnasios
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
}
