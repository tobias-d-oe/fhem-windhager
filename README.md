# fhem-windhager

fhem-windhager verbindet die Windhager Zentralheizung mittels RC7030 (myComfort) mit fhem
Zusätzlich zu den Readings wird ein Widgets für den Floorplan zur Verfügung gestellt.


Installation:
-----------------------------------------
Die Installation erfolgt manuell. Hierfür muss die Datei 77_WINDHAGER.pm in dem Ordner "fhem/FHEM/" abgelegt werden und mittels neustart von fhem oder einem "reload 77_WINDHAGER.pm" eingelesen werden.


Updates:
-----------------------------------------
In fhem kann mit folgendem Kommando das Modul upgedatet werden:

    update 77_WINDHAGER.pm https://raw.githubusercontent.com/tobias-d-oe/fhem-windhager/master/controls_windhager.txt


Verwendung:
-----------------------------------------
    define Zentralheizung WINDHAGER 192.168.0.30 Service geheimespw 300
    define <name> WINDHAGER <IP> <LoginName> <LoginPW> <INTERVAL>

Auch eine Funktion zur Benutzung durch weblink ist integriert:

    define ZentralheizungWidget weblink htmlCode {WINDHAGER_ASHTML()}

hierfür muss noch das Bild "ZentralHeizungSchema.png" nach fhem/www/images/default/ kopiert werden.
