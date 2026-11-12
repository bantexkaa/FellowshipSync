local _, addonTable = ...
addonTable.L = {}
local L = addonTable.L

L["ADDON_LOADED"] = "FellowshipSync v%s loaded. Type /fsync to open the Hall of Fame."
L["CACHE_WIPED"] = "FellowshipSync: Cleared all cached network characters."
L["SYNC_SENT"] = "FellowshipSync: Broadcasted your statistics to the guild."

---------------------------------------------------------------------------
-- Interface translations (German, French, Spanish). Keyed by the English text,
-- so anything without a translation simply stays English.
---------------------------------------------------------------------------

local DE = {
    ["Hall of Fame"] = "Ruhmeshalle", ["Deathlog"] = "Todesbuch", ["Combat"] = "Kampf", ["Misc & Gear"] = "Ausrüstung & Mehr",
    ["Profiles"] = "Profile", ["Faction War"] = "Fraktionskrieg", ["Chronicle"] = "Chronik", ["Fellowship"] = "Gefährten",
    ["Records"] = "Rekorde", ["Guild"] = "Gilde", ["Options"] = "Optionen", ["My Characters"] = "Meine Charaktere",
    ["Network"] = "Netzwerk", ["Accounts"] = "Accounts", ["All-Time"] = "Gesamt", ["This Week"] = "Diese Woche",
    ["Share"] = "Teilen", ["Export"] = "Exportieren", ["Send"] = "Senden", ["Compare"] = "Vergleichen", ["Back"] = "Zurück",
    ["Next"] = "Weiter", ["Finish"] = "Fertig", ["Remove"] = "Entfernen", ["Got it"] = "Verstanden", ["Make Rival"] = "Zum Rivalen machen",
    ["Book of Deeds"] = "Buch der Taten", ["Bonds"] = "Bande", ["Guild Bounties"] = "Gildenkopfgelder", ["Deathmap"] = "Todeskarte",
    ["Memory Lane"] = "Erinnerungen", ["Wagers"] = "Wetten", ["Rivalries"] = "Rivalitäten", ["Games"] = "Spiele",
    ["My Records"] = "Meine Rekorde", ["Zones"] = "Zonen", ["Loot"] = "Beute", ["Gold Flow"] = "Goldfluss", ["Survival"] = "Überleben",
    ["Social"] = "Soziales", ["Habits"] = "Gewohnheiten", ["Roster"] = "Mitglieder", ["Notices"] = "Mitteilungen", ["Polls"] = "Umfragen",
    ["Events"] = "Termine", ["Attendance"] = "Anwesenheit", ["Awards"] = "Auszeichnungen", ["Goals"] = "Ziele", ["Seasons"] = "Saisons",
    ["Bank"] = "Bank", ["Officers"] = "Offiziere", ["Character"] = "Charakter", ["Level"] = "Stufe", ["Class"] = "Klasse",
    ["Zone"] = "Zone", ["Kills"] = "Siege", ["Deaths"] = "Tode", ["Killer"] = "Mörder", ["Date"] = "Datum", ["Player"] = "Spieler",
    ["Member"] = "Mitglied", ["Rank"] = "Rang", ["Last Seen"] = "Zuletzt gesehen", ["Time"] = "Zeit", ["Stat"] = "Wert",
    ["Leader"] = "Führend", ["Gold Donated"] = "Gespendetes Gold", ["Cosmetics & UI"] = "Aussehen", ["Notifications"] = "Benachrichtigungen",
    ["Network & Sharing"] = "Netzwerk & Teilen", ["Data Privacy"] = "Datenschutz", ["Database Tools"] = "Datenbank",
    ["Share in Chat"] = "Im Chat teilen", ["Party / Raid"] = "Gruppe / Schlachtzug", ["Say"] = "Sagen",
    ["Click again to say it"] = "Zum Senden erneut klicken", ["Export (CSV)"] = "Export (CSV)", ["Nemesis"] = "Erzfeind", ["Award"] = "Auszeichnung",
    ["Press Ctrl+C to copy, then Esc to close."] = "Strg+C zum Kopieren, dann Esc zum Schließen.",
    ["Nothing to share here."] = "Hier gibt es nichts zu teilen.", ["There is no list to export here."] = "Hier gibt es keine Liste zum Exportieren.",
    ["You are not in a guild."] = "Du bist in keiner Gilde.", ["You are not in a group."] = "Du bist in keiner Gruppe.",
    ["What's new in FellowshipSync %s"] = "Neu in FellowshipSync %s", ["Pick two characters with the arrows above."] = "Wähle oben zwei Charaktere mit den Pfeilen.",
}
local FR = {
    ["Hall of Fame"] = "Panthéon", ["Deathlog"] = "Nécrologe", ["Combat"] = "Combat", ["Misc & Gear"] = "Équipement & divers",
    ["Profiles"] = "Profils", ["Faction War"] = "Guerre des factions", ["Chronicle"] = "Chronique", ["Fellowship"] = "Communauté",
    ["Records"] = "Records", ["Guild"] = "Guilde", ["Options"] = "Options", ["My Characters"] = "Mes personnages",
    ["Network"] = "Réseau", ["Accounts"] = "Comptes", ["All-Time"] = "Depuis toujours", ["This Week"] = "Cette semaine",
    ["Share"] = "Partager", ["Export"] = "Exporter", ["Send"] = "Envoyer", ["Compare"] = "Comparer", ["Back"] = "Retour",
    ["Next"] = "Suivant", ["Finish"] = "Terminer", ["Remove"] = "Retirer", ["Got it"] = "Compris", ["Make Rival"] = "Désigner rival",
    ["Book of Deeds"] = "Livre des exploits", ["Bonds"] = "Liens", ["Guild Bounties"] = "Primes de guilde", ["Deathmap"] = "Carte des morts",
    ["Memory Lane"] = "Souvenirs", ["Wagers"] = "Paris", ["Rivalries"] = "Rivalités", ["Games"] = "Jeux",
    ["My Records"] = "Mes records", ["Zones"] = "Zones", ["Loot"] = "Butin", ["Gold Flow"] = "Flux d'or", ["Survival"] = "Survie",
    ["Social"] = "Social", ["Habits"] = "Habitudes", ["Roster"] = "Membres", ["Notices"] = "Annonces", ["Polls"] = "Sondages",
    ["Events"] = "Événements", ["Attendance"] = "Présence", ["Awards"] = "Distinctions", ["Goals"] = "Objectifs", ["Seasons"] = "Saisons",
    ["Bank"] = "Banque", ["Officers"] = "Officiers", ["Character"] = "Personnage", ["Level"] = "Niveau", ["Class"] = "Classe",
    ["Zone"] = "Zone", ["Kills"] = "Victimes", ["Deaths"] = "Morts", ["Killer"] = "Tueur", ["Date"] = "Date", ["Player"] = "Joueur",
    ["Member"] = "Membre", ["Rank"] = "Rang", ["Last Seen"] = "Vu pour la dernière fois", ["Time"] = "Temps", ["Stat"] = "Statistique",
    ["Leader"] = "En tête", ["Gold Donated"] = "Or donné", ["Cosmetics & UI"] = "Apparence", ["Notifications"] = "Notifications",
    ["Network & Sharing"] = "Réseau & partage", ["Data Privacy"] = "Confidentialité", ["Database Tools"] = "Base de données",
    ["Share in Chat"] = "Partager dans le chat", ["Party / Raid"] = "Groupe / Raid", ["Say"] = "Dire",
    ["Click again to say it"] = "Cliquez encore pour l'envoyer", ["Export (CSV)"] = "Export (CSV)", ["Nemesis"] = "Ennemi juré", ["Award"] = "Distinction",
    ["Press Ctrl+C to copy, then Esc to close."] = "Ctrl+C pour copier, puis Échap pour fermer.",
    ["Nothing to share here."] = "Rien à partager ici.", ["There is no list to export here."] = "Aucune liste à exporter ici.",
    ["You are not in a guild."] = "Vous n'êtes pas dans une guilde.", ["You are not in a group."] = "Vous n'êtes pas dans un groupe.",
    ["What's new in FellowshipSync %s"] = "Nouveautés de FellowshipSync %s", ["Pick two characters with the arrows above."] = "Choisissez deux personnages avec les flèches.",
}
local ES = {
    ["Hall of Fame"] = "Salón de la Fama", ["Deathlog"] = "Registro de muertes", ["Combat"] = "Combate", ["Misc & Gear"] = "Equipo y más",
    ["Profiles"] = "Perfiles", ["Faction War"] = "Guerra de facciones", ["Chronicle"] = "Crónica", ["Fellowship"] = "Hermandad",
    ["Records"] = "Récords", ["Guild"] = "Hermandad", ["Options"] = "Opciones", ["My Characters"] = "Mis personajes",
    ["Network"] = "Red", ["Accounts"] = "Cuentas", ["All-Time"] = "Histórico", ["This Week"] = "Esta semana",
    ["Share"] = "Compartir", ["Export"] = "Exportar", ["Send"] = "Enviar", ["Compare"] = "Comparar", ["Back"] = "Atrás",
    ["Next"] = "Siguiente", ["Finish"] = "Terminar", ["Remove"] = "Quitar", ["Got it"] = "Entendido", ["Make Rival"] = "Hacer rival",
    ["Book of Deeds"] = "Libro de hazañas", ["Bonds"] = "Vínculos", ["Guild Bounties"] = "Recompensas", ["Deathmap"] = "Mapa de muertes",
    ["Memory Lane"] = "Recuerdos", ["Wagers"] = "Apuestas", ["Rivalries"] = "Rivalidades", ["Games"] = "Juegos",
    ["My Records"] = "Mis récords", ["Zones"] = "Zonas", ["Loot"] = "Botín", ["Gold Flow"] = "Flujo de oro", ["Survival"] = "Supervivencia",
    ["Social"] = "Social", ["Habits"] = "Hábitos", ["Roster"] = "Miembros", ["Notices"] = "Avisos", ["Polls"] = "Encuestas",
    ["Events"] = "Eventos", ["Attendance"] = "Asistencia", ["Awards"] = "Distinciones", ["Goals"] = "Objetivos", ["Seasons"] = "Temporadas",
    ["Bank"] = "Banco", ["Officers"] = "Oficiales", ["Character"] = "Personaje", ["Level"] = "Nivel", ["Class"] = "Clase",
    ["Zone"] = "Zona", ["Kills"] = "Muertes causadas", ["Deaths"] = "Muertes", ["Killer"] = "Asesino", ["Date"] = "Fecha", ["Player"] = "Jugador",
    ["Member"] = "Miembro", ["Rank"] = "Rango", ["Last Seen"] = "Visto por última vez", ["Time"] = "Tiempo", ["Stat"] = "Estadística",
    ["Leader"] = "Líder", ["Gold Donated"] = "Oro donado", ["Cosmetics & UI"] = "Apariencia", ["Notifications"] = "Notificaciones",
    ["Network & Sharing"] = "Red y compartir", ["Data Privacy"] = "Privacidad", ["Database Tools"] = "Base de datos",
    ["Share in Chat"] = "Compartir en el chat", ["Party / Raid"] = "Grupo / Banda", ["Say"] = "Decir",
    ["Click again to say it"] = "Haz clic otra vez para enviarlo", ["Export (CSV)"] = "Exportar (CSV)", ["Nemesis"] = "Némesis", ["Award"] = "Distinción",
    ["Press Ctrl+C to copy, then Esc to close."] = "Pulsa Ctrl+C para copiar y Esc para cerrar.",
    ["Nothing to share here."] = "No hay nada que compartir aquí.", ["There is no list to export here."] = "No hay ninguna lista para exportar aquí.",
    ["You are not in a guild."] = "No estás en una hermandad.", ["You are not in a group."] = "No estás en un grupo.",
    ["What's new in FellowshipSync %s"] = "Novedades de FellowshipSync %s", ["Pick two characters with the arrows above."] = "Elige dos personajes con las flechas.",
}

-- 3.8 additions
for k, v in pairs({ ["Leaderboards"] = "Bestenlisten", ["Players"] = "Spieler", ["History"] = "Geschichte", ["Pinned"] = "Angeheftet",
    ["Pin"] = "Anheften", ["Unpin"] = "Lösen", ["Basics"] = "Grundlagen", ["Search everything..."] = "Alles durchsuchen...",
    ["Nothing found."] = "Nichts gefunden.", ["Enemy"] = "Gegner", ["Boss"] = "Boss",
    ["Show all settings (Advanced)"] = "Alle Einstellungen (Erweitert)", ["Show fewer settings (Simple)"] = "Weniger Einstellungen (Einfach)" }) do DE[k] = v end
for k, v in pairs({ ["Leaderboards"] = "Classements", ["Players"] = "Joueurs", ["History"] = "Histoire", ["Pinned"] = "Épinglé",
    ["Pin"] = "Épingler", ["Unpin"] = "Désépingler", ["Basics"] = "Essentiel", ["Search everything..."] = "Tout rechercher...",
    ["Nothing found."] = "Aucun résultat.", ["Enemy"] = "Ennemi", ["Boss"] = "Boss",
    ["Show all settings (Advanced)"] = "Tous les réglages (Avancé)", ["Show fewer settings (Simple)"] = "Moins de réglages (Simple)" }) do FR[k] = v end
for k, v in pairs({ ["Leaderboards"] = "Clasificaciones", ["Players"] = "Jugadores", ["History"] = "Historia", ["Pinned"] = "Fijado",
    ["Pin"] = "Fijar", ["Unpin"] = "Soltar", ["Basics"] = "Básico", ["Search everything..."] = "Buscar en todo...",
    ["Nothing found."] = "Sin resultados.", ["Enemy"] = "Enemigo", ["Boss"] = "Jefe",
    ["Show all settings (Advanced)"] = "Todos los ajustes (Avanzado)", ["Show fewer settings (Simple)"] = "Menos ajustes (Simple)" }) do ES[k] = v end

for k, v in pairs({ ["Shame"] = "Schande", ["Luck"] = "Glück", ["Did you know?"] = "Wusstest du?", ["Hall of Shame"] = "Halle der Schande",
    ["Luck & Revenge"] = "Glück & Rache", ["Revenge!"] = "Rache!" }) do DE[k] = v end
for k, v in pairs({ ["Shame"] = "Honte", ["Luck"] = "Chance", ["Did you know?"] = "Le saviez-vous ?", ["Hall of Shame"] = "Mur de la honte",
    ["Luck & Revenge"] = "Chance & vengeance", ["Revenge!"] = "Vengeance !" }) do FR[k] = v end
for k, v in pairs({ ["Shame"] = "Vergüenza", ["Luck"] = "Suerte", ["Did you know?"] = "¿Sabías que?", ["Hall of Shame"] = "Muro de la vergüenza",
    ["Luck & Revenge"] = "Suerte y venganza", ["Revenge!"] = "¡Venganza!" }) do ES[k] = v end

local DICTS = { deDE = DE, frFR = FR, esES = ES, esMX = ES }
local active = DICTS[(GetLocale and GetLocale()) or "enUS"]
addonTable.T = function(text) return (active and active[text]) or text end
