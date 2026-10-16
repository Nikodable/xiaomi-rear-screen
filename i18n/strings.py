# Source unique des textes (FR, EN, DE, ES, IT, PT) — génère Strings.swift (Mac) et Strings.cs (Windows).
# Placeholders : {0} {1}… remplacés à l'exécution ; {pc} → « Mac » / « PC » à la génération.
# Les clés suffixées « .win » ou « .mac » remplacent la clé de base sur cette plateforme seulement.
LANGS = [("fr", "Français"), ("en", "English"), ("de", "Deutsch"), ("es", "Español"), ("it", "Italiano"), ("pt", "Português")]

S = {
"app.name": dict(fr="Écran arrière", en="Rear Screen", de="Rückdisplay", es="Pantalla trasera", it="Schermo posteriore", pt="Ecrã traseiro"),
"lang.label": dict(fr="Langue", en="Language", de="Sprache", es="Idioma", it="Lingua", pt="Idioma"),
"menu.quit": dict(fr="Quitter {0}", en="Quit {0}", de="{0} beenden", es="Salir de {0}", it="Esci da {0}", pt="Sair de {0}"),
"err.prepare": dict(fr="Impossible de préparer scrcpy/adb :\n{0}", en="Couldn't set up scrcpy/adb:\n{0}", de="scrcpy/adb konnte nicht vorbereitet werden:\n{0}", es="No se pudo preparar scrcpy/adb:\n{0}", it="Impossibile preparare scrcpy/adb:\n{0}", pt="Não foi possível preparar o scrcpy/adb:\n{0}"),

"status.searching": dict(fr="Recherche du téléphone…", en="Looking for the phone…", de="Suche nach dem Telefon …", es="Buscando el teléfono…", it="Ricerca del telefono…", pt="A procurar o telemóvel…"),
"status.noPhone": dict(
    fr="Aucun téléphone détecté. Vérifie le câble (mode « Transfert de fichiers ») et que le débogage USB est activé dans les options pour développeurs.",
    en="No phone detected. Check the cable (“File transfer” mode) and that USB debugging is turned on in Developer options.",
    de="Kein Telefon erkannt. Prüfe das Kabel (Modus „Dateiübertragung“) und ob das USB-Debugging in den Entwickleroptionen aktiviert ist.",
    es="No se detecta ningún teléfono. Comprueba el cable (modo «Transferencia de archivos») y que la depuración USB esté activada en las opciones de desarrollador.",
    it="Nessun telefono rilevato. Controlla il cavo (modalità «Trasferimento file») e che il debug USB sia attivo nelle opzioni sviluppatore.",
    pt="Nenhum telemóvel detetado. Verifica o cabo (modo «Transferência de ficheiros») e se a depuração USB está ativada nas opções de programador."),
"status.noPhone.win": dict(
    fr="Aucun téléphone détecté. Vérifie le câble (mode « Transfert de fichiers »), le pilote USB du téléphone et que le débogage USB est activé dans les options pour développeurs.",
    en="No phone detected. Check the cable (“File transfer” mode), the phone's USB driver and that USB debugging is turned on in Developer options.",
    de="Kein Telefon erkannt. Prüfe das Kabel (Modus „Dateiübertragung“), den USB-Treiber des Telefons und ob das USB-Debugging in den Entwickleroptionen aktiviert ist.",
    es="No se detecta ningún teléfono. Comprueba el cable (modo «Transferencia de archivos»), el controlador USB del teléfono y que la depuración USB esté activada en las opciones de desarrollador.",
    it="Nessun telefono rilevato. Controlla il cavo (modalità «Trasferimento file»), il driver USB del telefono e che il debug USB sia attivo nelle opzioni sviluppatore.",
    pt="Nenhum telemóvel detetado. Verifica o cabo (modo «Transferência de ficheiros»), o controlador USB do telemóvel e se a depuração USB está ativada nas opções de programador."),
"status.noDisplays": dict(fr="Téléphone détecté, mais ses écrans sont introuvables. Essaie ↻ ou rebranche-le.", en="Phone detected, but its screens could not be found. Try ↻ or reconnect it.", de="Telefon erkannt, aber die Displays wurden nicht gefunden. Versuche ↻ oder stecke es neu ein.", es="Teléfono detectado, pero no se encuentran sus pantallas. Prueba ↻ o vuelve a conectarlo.", it="Telefono rilevato, ma i suoi schermi non sono stati trovati. Prova ↻ o ricollegalo.", pt="Telemóvel detetado, mas os ecrãs não foram encontrados. Experimenta ↻ ou volta a ligá-lo."),
"status.connected": dict(fr="Téléphone connecté ✓", en="Phone connected ✓", de="Telefon verbunden ✓", es="Teléfono conectado ✓", it="Telefono connesso ✓", pt="Telemóvel ligado ✓"),
"status.unauthorized": dict(
    fr="Téléphone non autorisé : déverrouille-le et accepte « Autoriser le débogage USB » (coche « Toujours autoriser »).",
    en="Phone not authorized: unlock it and accept “Allow USB debugging” (tick “Always allow”).",
    de="Telefon nicht autorisiert: Entsperre es und bestätige „USB-Debugging zulassen“ (hake „Immer zulassen“ an).",
    es="Teléfono no autorizado: desbloquéalo y acepta «Permitir depuración USB» (marca «Permitir siempre»).",
    it="Telefono non autorizzato: sbloccalo e accetta «Consenti debug USB» (spunta «Consenti sempre»).",
    pt="Telemóvel não autorizado: desbloqueia-o e aceita «Permitir depuração USB» (marca «Permitir sempre»)."),
"status.offline": dict(fr="Téléphone hors ligne : débranche et rebranche le câble, ou redémarre le débogage USB.", en="Phone offline: unplug and replug the cable, or restart USB debugging.", de="Telefon offline: Ziehe das Kabel ab und stecke es wieder ein oder starte das USB-Debugging neu.", es="Teléfono sin conexión: desconecta y vuelve a conectar el cable, o reinicia la depuración USB.", it="Telefono offline: scollega e ricollega il cavo, oppure riavvia il debug USB.", pt="Telemóvel offline: desliga e volta a ligar o cabo, ou reinicia a depuração USB."),
"status.state": dict(fr="État du téléphone : {0}.", en="Phone state: {0}.", de="Telefonstatus: {0}.", es="Estado del teléfono: {0}.", it="Stato del telefono: {0}.", pt="Estado do telemóvel: {0}."),
"alert.noPhone": dict(fr="Aucun téléphone prêt", en="No phone ready", de="Kein Telefon bereit", es="Ningún teléfono listo", it="Nessun telefono pronto", pt="Nenhum telemóvel pronto"),

"label.phone": dict(fr="Téléphone", en="Phone", de="Telefon", es="Teléfono", it="Telefono", pt="Telemóvel"),
"label.display": dict(fr="Écran", en="Screen", de="Display", es="Pantalla", it="Schermo", pt="Ecrã"),
"label.quality": dict(fr="Qualité", en="Quality", de="Qualität", es="Calidad", it="Qualità", pt="Qualidade"),
"tip.refresh": dict(fr="Rechercher le téléphone", en="Look for the phone", de="Telefon suchen", es="Buscar el teléfono", it="Cerca il telefono", pt="Procurar o telemóvel"),
"phone.unauthorized": dict(fr="non autorisé", en="not authorized", de="nicht autorisiert", es="no autorizado", it="non autorizzato", pt="não autorizado"),

"display.front": dict(fr="Écran avant", en="Front screen", de="Vorderes Display", es="Pantalla frontal", it="Schermo anteriore", pt="Ecrã frontal"),
"display.rear": dict(fr="Écran arrière", en="Rear screen", de="Rückdisplay", es="Pantalla trasera", it="Schermo posteriore", pt="Ecrã traseiro"),
"display.main": dict(fr="Écran principal", en="Main screen", de="Hauptdisplay", es="Pantalla principal", it="Schermo principale", pt="Ecrã principal"),
"display.other": dict(fr="Écran {0}", en="Screen {0}", de="Display {0}", es="Pantalla {0}", it="Schermo {0}", pt="Ecrã {0}"),
"display.both": dict(fr="Les deux écrans", en="Both screens", de="Beide Displays", es="Las dos pantallas", it="Entrambi gli schermi", pt="Os dois ecrãs"),

"quality.light": dict(fr="Léger (4 Mb/s · 30 i/s)", en="Light (4 Mb/s · 30 fps)", de="Leicht (4 Mb/s · 30 fps)", es="Ligera (4 Mb/s · 30 fps)", it="Leggera (4 Mb/s · 30 fps)", pt="Leve (4 Mb/s · 30 fps)"),
"quality.normal": dict(fr="Normal (8 Mb/s · 60 i/s)", en="Normal (8 Mb/s · 60 fps)", de="Normal (8 Mb/s · 60 fps)", es="Normal (8 Mb/s · 60 fps)", it="Normale (8 Mb/s · 60 fps)", pt="Normal (8 Mb/s · 60 fps)"),
"quality.max": dict(fr="Max (20 Mb/s · 120 i/s)", en="Max (20 Mb/s · 120 fps)", de="Max (20 Mb/s · 120 fps)", es="Máx. (20 Mb/s · 120 fps)", it="Max (20 Mb/s · 120 fps)", pt="Máx. (20 Mb/s · 120 fps)"),

"mirror.start": dict(fr="▶  Miroir en direct", en="▶  Live mirror", de="▶  Live-Spiegelung", es="▶  Espejo en directo", it="▶  Mirroring in diretta", pt="▶  Espelho em direto"),
"mirror.stop": dict(fr="■  Arrêter le miroir", en="■  Stop mirror", de="■  Spiegelung beenden", es="■  Detener el espejo", it="■  Ferma il mirroring", pt="■  Parar o espelho"),
"rec.start": dict(fr="⏺  Enregistrer", en="⏺  Record", de="⏺  Aufnehmen", es="⏺  Grabar", it="⏺  Registra", pt="⏺  Gravar"),
"rec.stop": dict(fr="■  Arrêter l'enregistrement", en="■  Stop recording", de="■  Aufnahme beenden", es="■  Detener la grabación", it="■  Ferma la registrazione", pt="■  Parar a gravação"),
"rec.viewCheck": dict(fr="Afficher le miroir pendant l'enregistrement", en="Show the mirror while recording", de="Spiegelung während der Aufnahme anzeigen", es="Mostrar el espejo durante la grabación", it="Mostra il mirroring durante la registrazione", pt="Mostrar o espelho durante a gravação"),
"rec.inProgress": dict(fr="Un enregistrement est en cours : le miroir y est déjà inclus.", en="A recording is in progress: the mirror is already included.", de="Eine Aufnahme läuft: Die Spiegelung ist darin bereits enthalten.", es="Hay una grabación en curso: el espejo ya está incluido.", it="Registrazione in corso: il mirroring è già incluso.", pt="Há uma gravação em curso: o espelho já está incluído."),
"rec.saved": dict(fr="Enregistré : {0}", en="Saved: {0}", de="Gespeichert: {0}", es="Guardado: {0}", it="Salvato: {0}", pt="Guardado: {0}"),

"btn.photo": dict(fr="📷  Photo", en="📷  Photo", de="📷  Foto", es="📷  Foto", it="📷  Foto", pt="📷  Foto"),
"btn.folder": dict(fr="Ouvrir le dossier", en="Open folder", de="Ordner öffnen", es="Abrir la carpeta", it="Apri la cartella", pt="Abrir a pasta"),
"btn.wifi": dict(fr="📶  Passer en Wi-Fi", en="📶  Switch to Wi-Fi", de="📶  Auf WLAN wechseln", es="📶  Cambiar a Wi-Fi", it="📶  Passa al Wi-Fi", pt="📶  Mudar para Wi-Fi"),
"btn.manual": dict(fr="Connexion manuelle…", en="Manual connection…", de="Manuelle Verbindung …", es="Conexión manual…", it="Connessione manuale…", pt="Ligação manual…"),
"tip.wifi": dict(fr="Téléphone branché en USB : active la connexion sans fil, puis tu peux débrancher", en="Phone plugged in via USB: turns on the wireless connection, then you can unplug", de="Telefon per USB verbunden: aktiviert die drahtlose Verbindung, danach kannst du das Kabel abziehen", es="Teléfono conectado por USB: activa la conexión inalámbrica y después puedes desconectar el cable", it="Telefono collegato via USB: attiva la connessione wireless, poi puoi scollegare il cavo", pt="Telemóvel ligado por USB: ativa a ligação sem fios e depois podes desligar o cabo"),

"photo.capturing": dict(fr="Capture en cours…", en="Capturing…", de="Aufnahme läuft …", es="Capturando…", it="Acquisizione in corso…", pt="A capturar…"),
"photo.noId": dict(fr="Photo impossible : identifiant de l'écran {0} introuvable.", en="Photo failed: ID of screen {0} not found.", de="Foto nicht möglich: Kennung von Display {0} nicht gefunden.", es="No se pudo hacer la foto: identificador de la pantalla {0} no encontrado.", it="Foto non riuscita: identificatore dello schermo {0} non trovato.", pt="Foto impossível: identificador do ecrã {0} não encontrado."),
"photo.noImage": dict(fr="Photo impossible : le téléphone n'a pas renvoyé d'image (écran éteint ?).", en="Photo failed: the phone returned no image (screen off?).", de="Foto nicht möglich: Das Telefon hat kein Bild geliefert (Display aus?).", es="No se pudo hacer la foto: el teléfono no devolvió ninguna imagen (¿pantalla apagada?).", it="Foto non riuscita: il telefono non ha restituito alcuna immagine (schermo spento?).", pt="Foto impossível: o telemóvel não devolveu nenhuma imagem (ecrã desligado?)."),
"photo.writeFail": dict(fr="Photo impossible : écriture du fichier refusée.", en="Photo failed: could not write the file.", de="Foto nicht möglich: Datei konnte nicht geschrieben werden.", es="No se pudo hacer la foto: escritura del archivo denegada.", it="Foto non riuscita: scrittura del file rifiutata.", pt="Foto impossível: escrita do ficheiro recusada."),
"photo.done": dict(fr="Photo : {0}", en="Photo: {0}", de="Foto: {0}", es="Foto: {0}", it="Foto: {0}", pt="Foto: {0}"),

"wifi.already": dict(fr="Ce téléphone est déjà connecté en Wi-Fi.", en="This phone is already connected over Wi-Fi.", de="Dieses Telefon ist bereits per WLAN verbunden.", es="Este teléfono ya está conectado por Wi-Fi.", it="Questo telefono è già connesso via Wi-Fi.", pt="Este telemóvel já está ligado por Wi-Fi."),
"wifi.activating": dict(fr="Activation du Wi-Fi…", en="Turning on Wi-Fi…", de="WLAN wird aktiviert …", es="Activando el Wi-Fi…", it="Attivazione del Wi-Fi…", pt="A ativar o Wi-Fi…"),
"wifi.noWifi": dict(fr="Le téléphone n'est pas connecté à un Wi-Fi (même réseau que le {pc} requis).", en="The phone isn't connected to Wi-Fi (it must be on the same network as the {pc}).", de="Das Telefon ist nicht mit einem WLAN verbunden (es muss im selben Netzwerk wie der {pc} sein).", es="El teléfono no está conectado a una red Wi-Fi (debe estar en la misma red que el {pc}).", it="Il telefono non è connesso a una rete Wi-Fi (deve essere sulla stessa rete del {pc}).", pt="O telemóvel não está ligado a uma rede Wi-Fi (tem de estar na mesma rede que o {pc})."),
"wifi.ok": dict(fr="Wi-Fi activé ({0}) ✓ Tu peux débrancher le câble.", en="Wi-Fi on ({0}) ✓ You can unplug the cable.", de="WLAN aktiviert ({0}) ✓ Du kannst das Kabel abziehen.", es="Wi-Fi activado ({0}) ✓ Ya puedes desconectar el cable.", it="Wi-Fi attivato ({0}) ✓ Puoi scollegare il cavo.", pt="Wi-Fi ativado ({0}) ✓ Já podes desligar o cabo."),
"wifi.failed": dict(fr="Connexion Wi-Fi échouée : {0}", en="Wi-Fi connection failed: {0}", de="WLAN-Verbindung fehlgeschlagen: {0}", es="Error de conexión Wi-Fi: {0}", it="Connessione Wi-Fi non riuscita: {0}", pt="Falha na ligação Wi-Fi: {0}"),

"manual.title": dict(fr="Connexion sans fil", en="Wireless connection", de="Drahtlose Verbindung", es="Conexión inalámbrica", it="Connessione wireless", pt="Ligação sem fios"),
"manual.info": dict(
    fr="Sur le téléphone : Options pour les développeurs › Débogage sans fil. La 1re fois, « Associer avec un code » donne l'adresse d'appairage et le code ; ensuite, seule l'adresse de connexion suffit.",
    en="On the phone: Developer options › Wireless debugging. The first time, “Pair device with pairing code” gives you the pairing address and code; after that, the connection address is enough.",
    de="Am Telefon: Entwickleroptionen › Drahtloses Debugging. Beim ersten Mal liefert „Gerät mit Kopplungscode koppeln“ die Kopplungsadresse und den Code; danach genügt die Verbindungsadresse.",
    es="En el teléfono: Opciones de desarrollador › Depuración inalámbrica. La primera vez, «Vincular dispositivo con código de vinculación» da la dirección de vinculación y el código; después basta con la dirección de conexión.",
    it="Sul telefono: Opzioni sviluppatore › Debug wireless. La prima volta, «Associa dispositivo con codice di accoppiamento» fornisce l'indirizzo di accoppiamento e il codice; in seguito basta l'indirizzo di connessione.",
    pt="No telemóvel: Opções de programador › Depuração sem fios. À primeira vez, «Sincronizar dispositivo com código de sincronização» dá o endereço de sincronização e o código; depois, basta o endereço de ligação."),
"manual.pairAddr": dict(fr="Adresse d'appairage (1re fois seulement)", en="Pairing address (first time only)", de="Kopplungsadresse (nur beim ersten Mal)", es="Dirección de vinculación (solo la primera vez)", it="Indirizzo di accoppiamento (solo la prima volta)", pt="Endereço de sincronização (só à primeira vez)"),
"manual.code": dict(fr="Code d'appairage", en="Pairing code", de="Kopplungscode", es="Código de vinculación", it="Codice di accoppiamento", pt="Código de sincronização"),
"manual.connAddr": dict(fr="Adresse de connexion", en="Connection address", de="Verbindungsadresse", es="Dirección de conexión", it="Indirizzo di connessione", pt="Endereço de ligação"),
"manual.codeHint": dict(fr="6 chiffres", en="6 digits", de="6 Ziffern", es="6 dígitos", it="6 cifre", pt="6 dígitos"),
"manual.eg": dict(fr="ex. {0}", en="e.g. {0}", de="z. B. {0}", es="p. ej. {0}", it="es. {0}", pt="ex. {0}"),
"manual.connect": dict(fr="Connecter", en="Connect", de="Verbinden", es="Conectar", it="Connetti", pt="Ligar"),
"manual.cancel": dict(fr="Annuler", en="Cancel", de="Abbrechen", es="Cancelar", it="Annulla", pt="Cancelar"),
"manual.noAddr": dict(fr="Adresse de connexion manquante.", en="Connection address missing.", de="Verbindungsadresse fehlt.", es="Falta la dirección de conexión.", it="Indirizzo di connessione mancante.", pt="Falta o endereço de ligação."),
"manual.connecting": dict(fr="Connexion…", en="Connecting…", de="Verbindung wird hergestellt …", es="Conectando…", it="Connessione…", pt="A ligar…"),
"manual.ok": dict(fr="Connecté en Wi-Fi ✓", en="Connected over Wi-Fi ✓", de="Per WLAN verbunden ✓", es="Conectado por Wi-Fi ✓", it="Connesso via Wi-Fi ✓", pt="Ligado por Wi-Fi ✓"),
"manual.pairFailed": dict(fr="Appairage échoué : {0}", en="Pairing failed: {0}", de="Kopplung fehlgeschlagen: {0}", es="Error de vinculación: {0}", it="Accoppiamento non riuscito: {0}", pt="Falha na sincronização: {0}"),
"manual.failed": dict(fr="Connexion échouée : {0}", en="Connection failed: {0}", de="Verbindung fehlgeschlagen: {0}", es="Error de conexión: {0}", it="Connessione non riuscita: {0}", pt="Falha na ligação: {0}"),
}
