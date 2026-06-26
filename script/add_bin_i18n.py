#!/usr/bin/env python3
"""
Add bin i18n keys to all locale files.
"""
import json
import os

BASE = os.path.dirname(os.path.abspath(__file__))
LOCALES_DIR = os.path.join(BASE, '../app/javascript/i18n/locales')

BIN_TRANSLATIONS = {
    'en': {
        "title": "Recycle Bin",
        "subtitle": "Items deleted in the last {{days}} days. After that, they are permanently removed.",
        "empty": "Your recycle bin is empty",
        "emptySubtitle": "Deleted assets and folders will appear here.",
        "emptyBin": "Empty Bin",
        "restoreSelected": "Restore Selected",
        "deleteSelected": "Delete Selected",
        "search": "Search recycle bin\u2026",
        "results": "Results",
        "filters": {
            "all": "All Items", "assets": "Assets", "folders": "Folders",
            "images": "Images", "videos": "Videos", "documents": "Documents"
        },
        "sort": {
            "deletedNewest": "Deleted (Newest first)", "deletedOldest": "Deleted (Oldest first)",
            "nameAZ": "Name (A\u2013Z)", "nameZA": "Name (Z\u2013A)",
            "sizeDesc": "Size (Largest first)", "sizeAsc": "Size (Smallest first)"
        },
        "stats": { "totalItems": "Total Items", "assets": "Assets", "folders": "Folders", "storageUsed": "Storage Used" },
        "item": {
            "type": "Type", "name": "Name", "deletedAt": "Deleted", "size": "Size",
            "originalPath": "Location", "expires": "Expires", "actions": "Actions",
            "restore": "Restore", "deletePermanently": "Delete Permanently", "folder": "Folder", "asset": "Asset"
        },
        "retention": {
            "label": "Retention Policy", "description": "Items are auto-deleted after {{days}} days",
            "expires": "{{days}}d left", "expired": "Expired"
        },
        "confirm": {
            "restore": "Restore {{count}} item(s)?",
            "restoreBody": "Selected items will be moved back to their original location.",
            "delete": "Permanently delete {{count}} item(s)?",
            "deleteBody": "This cannot be undone. Files will be permanently removed from storage.",
            "emptyBin": "Empty the Recycle Bin?",
            "emptyBinBody": "All {{count}} items will be permanently deleted. This cannot be undone.",
            "confirm": "Confirm", "cancel": "Cancel"
        },
        "notifications": {
            "restored": "{{count}} item(s) restored successfully.",
            "deleted": "{{count}} item(s) permanently deleted.",
            "emptied": "Recycle bin emptied.",
            "loadError": "Failed to load recycle bin."
        },
        "pagination": { "prev": "Previous", "next": "Next", "info": "Page {{page}} of {{pages}}" }
    },
    'de': {
        "title": "Papierkorb",
        "subtitle": "Gel\u00f6schte Elemente der letzten {{days}} Tage. Danach werden sie dauerhaft entfernt.",
        "empty": "Ihr Papierkorb ist leer",
        "emptySubtitle": "Gel\u00f6schte Assets und Ordner erscheinen hier.",
        "emptyBin": "Papierkorb leeren",
        "restoreSelected": "Ausgew\u00e4hlte wiederherstellen",
        "deleteSelected": "Ausgew\u00e4hlte l\u00f6schen",
        "search": "Papierkorb durchsuchen\u2026",
        "results": "Ergebnisse",
        "filters": {
            "all": "Alle Elemente", "assets": "Assets", "folders": "Ordner",
            "images": "Bilder", "videos": "Videos", "documents": "Dokumente"
        },
        "sort": {
            "deletedNewest": "Gel\u00f6scht (Neueste zuerst)", "deletedOldest": "Gel\u00f6scht (\u00c4lteste zuerst)",
            "nameAZ": "Name (A\u2013Z)", "nameZA": "Name (Z\u2013A)",
            "sizeDesc": "Gr\u00f6\u00dfe (Gr\u00f6\u00dfte zuerst)", "sizeAsc": "Gr\u00f6\u00dfe (Kleinste zuerst)"
        },
        "stats": { "totalItems": "Elemente gesamt", "assets": "Assets", "folders": "Ordner", "storageUsed": "Speicher belegt" },
        "item": {
            "type": "Typ", "name": "Name", "deletedAt": "Gel\u00f6scht am", "size": "Gr\u00f6\u00dfe",
            "originalPath": "Speicherort", "expires": "L\u00e4uft ab", "actions": "Aktionen",
            "restore": "Wiederherstellen", "deletePermanently": "Dauerhaft l\u00f6schen", "folder": "Ordner", "asset": "Asset"
        },
        "retention": {
            "label": "Aufbewahrungsrichtlinie", "description": "Elemente werden nach {{days}} Tagen automatisch gel\u00f6scht",
            "expires": "Noch {{days}} Tage", "expired": "Abgelaufen"
        },
        "confirm": {
            "restore": "{{count}} Element(e) wiederherstellen?",
            "restoreBody": "Ausgew\u00e4hlte Elemente werden an ihren urspr\u00fcnglichen Speicherort zur\u00fcckgebracht.",
            "delete": "{{count}} Element(e) dauerhaft l\u00f6schen?",
            "deleteBody": "Dieser Vorgang kann nicht r\u00fcckg\u00e4ngig gemacht werden.",
            "emptyBin": "Papierkorb leeren?",
            "emptyBinBody": "Alle {{count}} Elemente werden dauerhaft gel\u00f6scht. Dies kann nicht r\u00fcckg\u00e4ngig gemacht werden.",
            "confirm": "Best\u00e4tigen", "cancel": "Abbrechen"
        },
        "notifications": {
            "restored": "{{count}} Element(e) erfolgreich wiederhergestellt.",
            "deleted": "{{count}} Element(e) dauerhaft gel\u00f6scht.",
            "emptied": "Papierkorb wurde geleert.",
            "loadError": "Papierkorb konnte nicht geladen werden."
        },
        "pagination": { "prev": "Zur\u00fcck", "next": "Weiter", "info": "Seite {{page}} von {{pages}}" }
    },
    'fr': {
        "title": "Corbeille",
        "subtitle": "El\u00e9ments supprim\u00e9s ces {{days}} derniers jours. Apr\u00e8s cela, ils sont supprim\u00e9s d\u00e9finitivement.",
        "empty": "Votre corbeille est vide",
        "emptySubtitle": "Les assets et dossiers supprim\u00e9s appara\u00eetront ici.",
        "emptyBin": "Vider la corbeille",
        "restoreSelected": "Restaurer la s\u00e9lection",
        "deleteSelected": "Supprimer la s\u00e9lection",
        "search": "Rechercher dans la corbeille\u2026",
        "results": "R\u00e9sultats",
        "filters": {
            "all": "Tous les \u00e9l\u00e9ments", "assets": "Assets", "folders": "Dossiers",
            "images": "Images", "videos": "Vid\u00e9os", "documents": "Documents"
        },
        "sort": {
            "deletedNewest": "Supprim\u00e9 (Plus r\u00e9cent)", "deletedOldest": "Supprim\u00e9 (Plus ancien)",
            "nameAZ": "Nom (A\u2013Z)", "nameZA": "Nom (Z\u2013A)",
            "sizeDesc": "Taille (Plus grande)", "sizeAsc": "Taille (Plus petite)"
        },
        "stats": { "totalItems": "Total des \u00e9l\u00e9ments", "assets": "Assets", "folders": "Dossiers", "storageUsed": "Stockage utilis\u00e9" },
        "item": {
            "type": "Type", "name": "Nom", "deletedAt": "Supprim\u00e9 le", "size": "Taille",
            "originalPath": "Emplacement", "expires": "Expire le", "actions": "Actions",
            "restore": "Restaurer", "deletePermanently": "Supprimer d\u00e9finitivement", "folder": "Dossier", "asset": "Asset"
        },
        "retention": {
            "label": "Politique de r\u00e9tention", "description": "Les \u00e9l\u00e9ments sont supprim\u00e9s automatiquement apr\u00e8s {{days}} jours",
            "expires": "{{days}}j restants", "expired": "Expir\u00e9"
        },
        "confirm": {
            "restore": "Restaurer {{count}} \u00e9l\u00e9ment(s)\u00a0?",
            "restoreBody": "Les \u00e9l\u00e9ments s\u00e9lectionn\u00e9s seront remis \u00e0 leur emplacement d'origine.",
            "delete": "Supprimer d\u00e9finitivement {{count}} \u00e9l\u00e9ment(s)\u00a0?",
            "deleteBody": "Cette action est irr\u00e9versible. Les fichiers seront supprim\u00e9s du stockage.",
            "emptyBin": "Vider la corbeille\u00a0?",
            "emptyBinBody": "Tous les {{count}} \u00e9l\u00e9ments seront supprim\u00e9s d\u00e9finitivement. Cette action est irr\u00e9versible.",
            "confirm": "Confirmer", "cancel": "Annuler"
        },
        "notifications": {
            "restored": "{{count}} \u00e9l\u00e9ment(s) restaur\u00e9(s) avec succ\u00e8s.",
            "deleted": "{{count}} \u00e9l\u00e9ment(s) supprim\u00e9(s) d\u00e9finitivement.",
            "emptied": "Corbeille vid\u00e9e.",
            "loadError": "Impossible de charger la corbeille."
        },
        "pagination": { "prev": "Pr\u00e9c\u00e9dent", "next": "Suivant", "info": "Page {{page}} sur {{pages}}" }
    },
    'es': {
        "title": "Papelera de reciclaje",
        "subtitle": "Elementos eliminados en los \u00faltimos {{days}} d\u00edas. Despu\u00e9s se eliminan definitivamente.",
        "empty": "Tu papelera est\u00e1 vac\u00eda",
        "emptySubtitle": "Los assets y carpetas eliminados aparecer\u00e1n aqu\u00ed.",
        "emptyBin": "Vaciar papelera",
        "restoreSelected": "Restaurar selecci\u00f3n",
        "deleteSelected": "Eliminar selecci\u00f3n",
        "search": "Buscar en papelera\u2026",
        "results": "Resultados",
        "filters": {
            "all": "Todos los elementos", "assets": "Assets", "folders": "Carpetas",
            "images": "Im\u00e1genes", "videos": "Videos", "documents": "Documentos"
        },
        "sort": {
            "deletedNewest": "Eliminado (M\u00e1s reciente)", "deletedOldest": "Eliminado (M\u00e1s antiguo)",
            "nameAZ": "Nombre (A\u2013Z)", "nameZA": "Nombre (Z\u2013A)",
            "sizeDesc": "Tama\u00f1o (Mayor primero)", "sizeAsc": "Tama\u00f1o (Menor primero)"
        },
        "stats": { "totalItems": "Total de elementos", "assets": "Assets", "folders": "Carpetas", "storageUsed": "Almacenamiento usado" },
        "item": {
            "type": "Tipo", "name": "Nombre", "deletedAt": "Eliminado", "size": "Tama\u00f1o",
            "originalPath": "Ubicaci\u00f3n", "expires": "Expira", "actions": "Acciones",
            "restore": "Restaurar", "deletePermanently": "Eliminar permanentemente", "folder": "Carpeta", "asset": "Asset"
        },
        "retention": {
            "label": "Pol\u00edtica de retenci\u00f3n", "description": "Los elementos se eliminan autom\u00e1ticamente despu\u00e9s de {{days}} d\u00edas",
            "expires": "{{days}}d restantes", "expired": "Expirado"
        },
        "confirm": {
            "restore": "\u00bfRestaurar {{count}} elemento(s)?",
            "restoreBody": "Los elementos seleccionados se mover\u00e1n de vuelta a su ubicaci\u00f3n original.",
            "delete": "\u00bfEliminar permanentemente {{count}} elemento(s)?",
            "deleteBody": "Esta acci\u00f3n no se puede deshacer. Los archivos se eliminar\u00e1n del almacenamiento.",
            "emptyBin": "\u00bfVaciar la papelera de reciclaje?",
            "emptyBinBody": "Todos los {{count}} elementos se eliminar\u00e1n permanentemente. Esta acci\u00f3n no se puede deshacer.",
            "confirm": "Confirmar", "cancel": "Cancelar"
        },
        "notifications": {
            "restored": "{{count}} elemento(s) restaurado(s) con \u00e9xito.",
            "deleted": "{{count}} elemento(s) eliminado(s) permanentemente.",
            "emptied": "Papelera vaciada.",
            "loadError": "Error al cargar la papelera."
        },
        "pagination": { "prev": "Anterior", "next": "Siguiente", "info": "P\u00e1gina {{page}} de {{pages}}" }
    },
    'ja': {
        "title": "\u30b4\u30df\u7b71",
        "subtitle": "\u904e\u53bb{{days}}\u65e5\u9593\u306b\u524a\u9664\u3055\u308c\u305f\u30a2\u30a4\u30c6\u30e0\u3002\u305d\u306e\u5f8c\u3001\u6c38\u4e45\u306b\u524a\u9664\u3055\u308c\u307e\u3059\u3002",
        "empty": "\u30b4\u30df\u7b71\u306f\u7a7a\u3067\u3059",
        "emptySubtitle": "\u524a\u9664\u3055\u308c\u305f\u30a2\u30bb\u30c3\u30c8\u3068\u30d5\u30a9\u30eb\u30c0\u304c\u3053\u3053\u306b\u8868\u793a\u3055\u308c\u307e\u3059\u3002",
        "emptyBin": "\u30b4\u30df\u7b71\u3092\u7a7a\u306b\u3059\u308b",
        "restoreSelected": "\u9078\u629e\u3057\u305f\u9805\u76ee\u3092\u5fa9\u5143",
        "deleteSelected": "\u9078\u629e\u3057\u305f\u9805\u76ee\u3092\u524a\u9664",
        "search": "\u30b4\u30df\u7b71\u3092\u691c\u7d22\u2026",
        "results": "\u4ef6",
        "filters": {
            "all": "\u3059\u3079\u3066\u306e\u30a2\u30a4\u30c6\u30e0", "assets": "\u30a2\u30bb\u30c3\u30c8", "folders": "\u30d5\u30a9\u30eb\u30c0",
            "images": "\u753b\u50cf", "videos": "\u52d5\u753b", "documents": "\u30c9\u30ad\u30e5\u30e1\u30f3\u30c8"
        },
        "sort": {
            "deletedNewest": "\u524a\u9664\u65e5\u6642\uff08\u65b0\u3057\u3044\u9806\uff09", "deletedOldest": "\u524a\u9664\u65e5\u6642\uff08\u53e4\u3044\u9806\uff09",
            "nameAZ": "\u540d\u524d (A\u2013Z)", "nameZA": "\u540d\u524d (Z\u2013A)",
            "sizeDesc": "\u30b5\u30a4\u30ba\uff08\u5927\u304d\u3044\u9806\uff09", "sizeAsc": "\u30b5\u30a4\u30ba\uff08\u5c0f\u3055\u3044\u9806\uff09"
        },
        "stats": { "totalItems": "\u30a2\u30a4\u30c6\u30e0\u5408\u8a08", "assets": "\u30a2\u30bb\u30c3\u30c8", "folders": "\u30d5\u30a9\u30eb\u30c0", "storageUsed": "\u4f7f\u7528\u30b9\u30c8\u30ec\u30fc\u30b8" },
        "item": {
            "type": "\u7a2e\u985e", "name": "\u540d\u524d", "deletedAt": "\u524a\u9664\u65e5\u6642", "size": "\u30b5\u30a4\u30ba",
            "originalPath": "\u5143\u306e\u5834\u6240", "expires": "\u6709\u52b9\u671f\u9650", "actions": "\u64cd\u4f5c",
            "restore": "\u5fa9\u5143", "deletePermanently": "\u6c38\u4e45\u524a\u9664", "folder": "\u30d5\u30a9\u30eb\u30c0", "asset": "\u30a2\u30bb\u30c3\u30c8"
        },
        "retention": {
            "label": "\u4fdd\u6301\u30dd\u30ea\u30b7\u30fc", "description": "{{days}}\u65e5\u5f8c\u306b\u81ea\u52d5\u524a\u9664\u3055\u308c\u307e\u3059",
            "expires": "\u6b8b\u308a{{days}}\u65e5", "expired": "\u671f\u9650\u5207\u308c"
        },
        "confirm": {
            "restore": "{{count}}\u4ef6\u3092\u5fa9\u5143\u3057\u307e\u3059\u304b\uff1f",
            "restoreBody": "\u9078\u629e\u3057\u305f\u30a2\u30a4\u30c6\u30e0\u306f\u5143\u306e\u5834\u6240\u306b\u623b\u3055\u308c\u307e\u3059\u3002",
            "delete": "{{count}}\u4ef6\u3092\u6c38\u4e45\u524a\u9664\u3057\u307e\u3059\u304b\uff1f",
            "deleteBody": "\u3053\u306e\u64cd\u4f5c\u306f\u5143\u306b\u623b\u305b\u307e\u305b\u3093\u3002\u30d5\u30a1\u30a4\u30eb\u306f\u30b9\u30c8\u30ec\u30fc\u30b8\u304b\u3089\u6c38\u4e45\u306b\u524a\u9664\u3055\u308c\u307e\u3059\u3002",
            "emptyBin": "\u30b4\u30df\u7b71\u3092\u7a7a\u306b\u3057\u307e\u3059\u304b\uff1f",
            "emptyBinBody": "\u5168{{count}}\u4ef6\u304c\u6c38\u4e45\u306b\u524a\u9664\u3055\u308c\u307e\u3059\u3002\u3053\u306e\u64cd\u4f5c\u306f\u5143\u306b\u623b\u305b\u307e\u305b\u3093\u3002",
            "confirm": "\u78ba\u8a8d", "cancel": "\u30ad\u30e3\u30f3\u30bb\u30eb"
        },
        "notifications": {
            "restored": "{{count}}\u4ef6\u3092\u5fa9\u5143\u3057\u307e\u3057\u305f\u3002",
            "deleted": "{{count}}\u4ef6\u3092\u6c38\u4e45\u524a\u9664\u3057\u307e\u3057\u305f\u3002",
            "emptied": "\u30b4\u30df\u7b71\u3092\u7a7a\u306b\u3057\u307e\u3057\u305f\u3002",
            "loadError": "\u30b4\u30df\u7b71\u306e\u8aad\u307f\u8fbc\u307f\u306b\u5931\u6557\u3057\u307e\u3057\u305f\u3002"
        },
        "pagination": { "prev": "\u524d\u3078", "next": "\u6b21\u3078", "info": "{{pages}}\u30da\u30fc\u30b8\u4e2d{{page}}\u30da\u30fc\u30b8" }
    },
    'ko': {
        "title": "\ud734\uc9c0\ud1b5",
        "subtitle": "\uc9c0\ub09c {{days}}\uc77c \ub3d9\uc548 \uc0ad\uc81c\ub41c \ud56d\ubaa9\uc785\ub2c8\ub2e4. \uadf8 \uc774\ud6c4\ub294 \uc601\uad6c\uc801\uc73c\ub85c \uc81c\uac70\ub429\ub2c8\ub2e4.",
        "empty": "\ud734\uc9c0\ud1b5\uc774 \ube44\uc5b4 \uc788\uc2b5\ub2c8\ub2e4",
        "emptySubtitle": "\uc0ad\uc81c\ub41c \uc5d0\uc14b\uacfc \ud3f4\ub354\uac00 \uc5ec\uae30\uc5d0 \ud45c\uc2dc\ub429\ub2c8\ub2e4.",
        "emptyBin": "\ud734\uc9c0\ud1b5 \ube44\uc6b0\uae30",
        "restoreSelected": "\uc120\ud0dd \ud56d\ubaa9 \ubcf5\uc6d0",
        "deleteSelected": "\uc120\ud0dd \ud56d\ubaa9 \uc0ad\uc81c",
        "search": "\ud734\uc9c0\ud1b5 \uac80\uc0c9\u2026",
        "results": "\uacb0\uacfc",
        "filters": {
            "all": "\ubaa8\ub4e0 \ud56d\ubaa9", "assets": "\uc5d0\uc14b", "folders": "\ud3f4\ub354",
            "images": "\uc774\ubbf8\uc9c0", "videos": "\ube44\ub514\uc624", "documents": "\ubb38\uc11c"
        },
        "sort": {
            "deletedNewest": "\uc0ad\uc81c\uc77c (\uc5ec\ub2e4 \uc21c)", "deletedOldest": "\uc0ad\uc81c\uc77c (\uc624\ub798\ub41c \uc21c)",
            "nameAZ": "\uc774\ub984 (A\u2013Z)", "nameZA": "\uc774\ub984 (Z\u2013A)",
            "sizeDesc": "\ud06c\uae30 (\ud070 \uc21c)", "sizeAsc": "\ud06c\uae30 (\uc791\uc740 \uc21c)"
        },
        "stats": { "totalItems": "\uc804\uccb4 \ud56d\ubaa9", "assets": "\uc5d0\uc14b", "folders": "\ud3f4\ub354", "storageUsed": "\uc0ac\uc6a9 \uc800\uc7a5\uc18c" },
        "item": {
            "type": "\uc720\ud615", "name": "\uc774\ub984", "deletedAt": "\uc0ad\uc81c\uc77c", "size": "\ud06c\uae30",
            "originalPath": "\uc704\uce58", "expires": "\ub9cc\ub8cc", "actions": "\uc791\uc5c5",
            "restore": "\ubcf5\uc6d0", "deletePermanently": "\uc601\uad6c \uc0ad\uc81c", "folder": "\ud3f4\ub354", "asset": "\uc5d0\uc14b"
        },
        "retention": {
            "label": "\ubcf4\uc720 \uc815\ucc45", "description": "{{days}}\uc77c \ud6c4 \uc790\ub3d9 \uc0ad\uc81c",
            "expires": "{{days}}\uc77c \ub0a8\uc74c", "expired": "\ub9cc\ub8cc"
        },
        "confirm": {
            "restore": "{{count}}\uac1c \ud56d\ubaa9\uc744 \ubcf5\uc6d0\ud558\uc2dc\uaca0\uc2b5\ub2c8\uae4c?",
            "restoreBody": "\uc120\ud0dd\ud55c \ud56d\ubaa9\uc774 \uc6d0\ub798 \uc704\uce58\ub85c \uc774\ub3d9\ub429\ub2c8\ub2e4.",
            "delete": "{{count}}\uac1c \ud56d\ubaa9\uc744 \uc601\uad6c \uc0ad\uc81c\ud558\uc2dc\uaca0\uc2b5\ub2c8\uae4c?",
            "deleteBody": "\uc774 \uc791\uc5c5\uc740 \uc2e4\ud589 \ucde8\uc18c\ud560 \uc218 \uc5c6\uc2b5\ub2c8\ub2e4.",
            "emptyBin": "\ud734\uc9c0\ud1b5\uc744 \ube44\uc6b0\uc2dc\uaca0\uc2b5\ub2c8\uae4c?",
            "emptyBinBody": "\ubaa8\ub4e0 {{count}}\uac1c \ud56d\ubaa9\uc774 \uc601\uad6c\uc801\uc73c\ub85c \uc0ad\uc81c\ub429\ub2c8\ub2e4.",
            "confirm": "\ud655\uc778", "cancel": "\ucde8\uc18c"
        },
        "notifications": {
            "restored": "{{count}}\uac1c \ud56d\ubaa9\uc774 \ubcf5\uc6d0\ub418\uc5c8\uc2b5\ub2c8\ub2e4.",
            "deleted": "{{count}}\uac1c \ud56d\ubaa9\uc774 \uc601\uad6c \uc0ad\uc81c\ub418\uc5c8\uc2b5\ub2c8\ub2e4.",
            "emptied": "\ud734\uc9c0\ud1b5\uc774 \ube44\uc5b4\uc84c\uc2b5\ub2c8\ub2e4.",
            "loadError": "\ud734\uc9c0\ud1b5\uc744 \ub85c\ub4dc\ud558\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4."
        },
        "pagination": { "prev": "\uc774\uc804", "next": "\ub2e4\uc74c", "info": "{{pages}}\ud398\uc774\uc9c0 \uc911 {{page}}\ud398\uc774\uc9c0" }
    },
    'nl': {
        "title": "Prullenbak",
        "subtitle": "Items verwijderd in de afgelopen {{days}} dagen. Daarna worden ze permanent verwijderd.",
        "empty": "Uw prullenbak is leeg",
        "emptySubtitle": "Verwijderde assets en mappen verschijnen hier.",
        "emptyBin": "Prullenbak leegmaken",
        "restoreSelected": "Selectie herstellen",
        "deleteSelected": "Selectie verwijderen",
        "search": "Zoeken in prullenbak\u2026",
        "results": "Resultaten",
        "filters": {
            "all": "Alle items", "assets": "Assets", "folders": "Mappen",
            "images": "Afbeeldingen", "videos": "Video's", "documents": "Documenten"
        },
        "sort": {
            "deletedNewest": "Verwijderd (Nieuwste eerst)", "deletedOldest": "Verwijderd (Oudste eerst)",
            "nameAZ": "Naam (A\u2013Z)", "nameZA": "Naam (Z\u2013A)",
            "sizeDesc": "Grootte (Grootste eerst)", "sizeAsc": "Grootte (Kleinste eerst)"
        },
        "stats": { "totalItems": "Totaal items", "assets": "Assets", "folders": "Mappen", "storageUsed": "Opslag gebruikt" },
        "item": {
            "type": "Type", "name": "Naam", "deletedAt": "Verwijderd op", "size": "Grootte",
            "originalPath": "Locatie", "expires": "Verloopt op", "actions": "Acties",
            "restore": "Herstellen", "deletePermanently": "Permanent verwijderen", "folder": "Map", "asset": "Asset"
        },
        "retention": {
            "label": "Bewaarbeleid", "description": "Items worden na {{days}} dagen automatisch verwijderd",
            "expires": "Nog {{days}} dagen", "expired": "Verlopen"
        },
        "confirm": {
            "restore": "{{count}} item(s) herstellen?",
            "restoreBody": "Geselecteerde items worden teruggebracht naar hun oorspronkelijke locatie.",
            "delete": "{{count}} item(s) permanent verwijderen?",
            "deleteBody": "Deze actie kan niet ongedaan worden gemaakt.",
            "emptyBin": "Prullenbak leegmaken?",
            "emptyBinBody": "Alle {{count}} items worden permanent verwijderd. Dit kan niet ongedaan worden gemaakt.",
            "confirm": "Bevestigen", "cancel": "Annuleren"
        },
        "notifications": {
            "restored": "{{count}} item(s) succesvol hersteld.",
            "deleted": "{{count}} item(s) permanent verwijderd.",
            "emptied": "Prullenbak leeggemaakt.",
            "loadError": "Prullenbak kon niet worden geladen."
        },
        "pagination": { "prev": "Vorige", "next": "Volgende", "info": "Pagina {{page}} van {{pages}}" }
    },
    'pt': {
        "title": "Lixeira",
        "subtitle": "Itens exclu\u00eddos nos \u00faltimos {{days}} dias. Ap\u00f3s isso, s\u00e3o removidos permanentemente.",
        "empty": "Sua lixeira est\u00e1 vazia",
        "emptySubtitle": "Assets e pastas exclu\u00eddos aparecer\u00e3o aqui.",
        "emptyBin": "Esvaziar lixeira",
        "restoreSelected": "Restaurar selecionados",
        "deleteSelected": "Excluir selecionados",
        "search": "Pesquisar na lixeira\u2026",
        "results": "Resultados",
        "filters": {
            "all": "Todos os itens", "assets": "Assets", "folders": "Pastas",
            "images": "Imagens", "videos": "V\u00eddeos", "documents": "Documentos"
        },
        "sort": {
            "deletedNewest": "Exclu\u00eddo (Mais recente)", "deletedOldest": "Exclu\u00eddo (Mais antigo)",
            "nameAZ": "Nome (A\u2013Z)", "nameZA": "Nome (Z\u2013A)",
            "sizeDesc": "Tamanho (Maior primeiro)", "sizeAsc": "Tamanho (Menor primeiro)"
        },
        "stats": { "totalItems": "Total de itens", "assets": "Assets", "folders": "Pastas", "storageUsed": "Armazenamento usado" },
        "item": {
            "type": "Tipo", "name": "Nome", "deletedAt": "Exclu\u00eddo em", "size": "Tamanho",
            "originalPath": "Localiza\u00e7\u00e3o", "expires": "Expira em", "actions": "A\u00e7\u00f5es",
            "restore": "Restaurar", "deletePermanently": "Excluir permanentemente", "folder": "Pasta", "asset": "Asset"
        },
        "retention": {
            "label": "Pol\u00edtica de reten\u00e7\u00e3o", "description": "Itens s\u00e3o exclu\u00eddos automaticamente ap\u00f3s {{days}} dias",
            "expires": "{{days}} dias restantes", "expired": "Expirado"
        },
        "confirm": {
            "restore": "Restaurar {{count}} item(ns)?",
            "restoreBody": "Os itens selecionados ser\u00e3o movidos de volta para o local de origem.",
            "delete": "Excluir permanentemente {{count}} item(ns)?",
            "deleteBody": "Esta a\u00e7\u00e3o n\u00e3o pode ser desfeita.",
            "emptyBin": "Esvaziar a lixeira?",
            "emptyBinBody": "Todos os {{count}} itens ser\u00e3o exclu\u00eddos permanentemente. N\u00e3o pode ser desfeito.",
            "confirm": "Confirmar", "cancel": "Cancelar"
        },
        "notifications": {
            "restored": "{{count}} item(ns) restaurado(s) com sucesso.",
            "deleted": "{{count}} item(ns) exclu\u00eddo(s) permanentemente.",
            "emptied": "Lixeira esvaziada.",
            "loadError": "Falha ao carregar a lixeira."
        },
        "pagination": { "prev": "Anterior", "next": "Pr\u00f3ximo", "info": "P\u00e1gina {{page}} de {{pages}}" }
    },
    'zh': {
        "title": "\u56de\u6536\u7ad9",
        "subtitle": "\u8fc7\u53bb {{days}} \u5929\u5185\u5220\u9664\u7684\u9879\u76ee\u3002\u4e4b\u540e\u5c06\u88ab\u6c38\u4e45\u5220\u9664\u3002",
        "empty": "\u56de\u6536\u7ad9\u4e3a\u7a7a",
        "emptySubtitle": "\u5df2\u5220\u9664\u7684\u8d44\u6e90\u548c\u6587\u4ef6\u5939\u5c06\u5728\u6b64\u663e\u793a\u3002",
        "emptyBin": "\u6e05\u7a7a\u56de\u6536\u7ad9",
        "restoreSelected": "\u6062\u590d\u9009\u4e2d\u9879\u76ee",
        "deleteSelected": "\u5220\u9664\u9009\u4e2d\u9879\u76ee",
        "search": "\u641c\u7d22\u56de\u6536\u7ad9\u2026",
        "results": "\u7ed3\u679c",
        "filters": {
            "all": "\u6240\u6709\u9879\u76ee", "assets": "\u8d44\u6e90", "folders": "\u6587\u4ef6\u5939",
            "images": "\u56fe\u7247", "videos": "\u89c6\u9891", "documents": "\u6587\u6863"
        },
        "sort": {
            "deletedNewest": "\u5220\u9664\u65f6\u95f4\uff08\u6700\u65b0\uff09", "deletedOldest": "\u5220\u9664\u65f6\u95f4\uff08\u6700\u65e7\uff09",
            "nameAZ": "\u540d\u79f0 (A\u2013Z)", "nameZA": "\u540d\u79f0 (Z\u2013A)",
            "sizeDesc": "\u5927\u5c0f\uff08\u6700\u5927\uff09", "sizeAsc": "\u5927\u5c0f\uff08\u6700\u5c0f\uff09"
        },
        "stats": { "totalItems": "\u603b\u9879\u76ee", "assets": "\u8d44\u6e90", "folders": "\u6587\u4ef6\u5939", "storageUsed": "\u5df2\u7528\u5b58\u50a8" },
        "item": {
            "type": "\u7c7b\u578b", "name": "\u540d\u79f0", "deletedAt": "\u5220\u9664\u65f6\u95f4", "size": "\u5927\u5c0f",
            "originalPath": "\u4f4d\u7f6e", "expires": "\u5230\u671f", "actions": "\u64cd\u4f5c",
            "restore": "\u6062\u590d", "deletePermanently": "\u6c38\u4e45\u5220\u9664", "folder": "\u6587\u4ef6\u5939", "asset": "\u8d44\u6e90"
        },
        "retention": {
            "label": "\u4fdd\u7559\u7b56\u7565", "description": "\u9879\u76ee\u5c06\u5728 {{days}} \u5929\u540e\u81ea\u52a8\u5220\u9664",
            "expires": "\u8fd8\u5269 {{days}} \u5929", "expired": "\u5df2\u8fc7\u671f"
        },
        "confirm": {
            "restore": "\u6062\u590d {{count}} \u4e2a\u9879\u76ee\uff1f",
            "restoreBody": "\u9009\u4e2d\u7684\u9879\u76ee\u5c06\u88ab\u79fb\u56de\u5176\u539f\u59cb\u4f4d\u7f6e\u3002",
            "delete": "\u6c38\u4e45\u5220\u9664 {{count}} \u4e2a\u9879\u76ee\uff1f",
            "deleteBody": "\u6b64\u64cd\u4f5c\u65e0\u6cd5\u64a4\u9500\u3002\u6587\u4ef6\u5c06\u4ece\u5b58\u50a8\u4e2d\u6c38\u4e45\u5220\u9664\u3002",
            "emptyBin": "\u6e05\u7a7a\u56de\u6536\u7ad9\uff1f",
            "emptyBinBody": "\u6240\u6709 {{count}} \u4e2a\u9879\u76ee\u5c06\u88ab\u6c38\u4e45\u5220\u9664\u3002\u6b64\u64cd\u4f5c\u65e0\u6cd5\u64a4\u9500\u3002",
            "confirm": "\u786e\u8ba4", "cancel": "\u53d6\u6d88"
        },
        "notifications": {
            "restored": "\u5df2\u6210\u529f\u6062\u590d {{count}} \u4e2a\u9879\u76ee\u3002",
            "deleted": "\u5df2\u6c38\u4e45\u5220\u9664 {{count}} \u4e2a\u9879\u76ee\u3002",
            "emptied": "\u56de\u6536\u7ad9\u5df2\u6e05\u7a7a\u3002",
            "loadError": "\u52a0\u8f7d\u56de\u6536\u7ad9\u5931\u8d25\u3002"
        },
        "pagination": { "prev": "\u4e0a\u4e00\u9875", "next": "\u4e0b\u4e00\u9875", "info": "\u7b2c {{page}} \u9875\uff0c\u5171 {{pages}} \u9875" }
    },
}

def add_bin_keys(locale_code, translations):
    filepath = os.path.join(LOCALES_DIR, f'{locale_code}.json')
    if not os.path.exists(filepath):
        print(f'  SKIP: {filepath} not found')
        return

    with open(filepath, 'r', encoding='utf-8') as f:
        data = json.load(f)

    if 'bin' in data:
        print(f'  SKIP {locale_code}: bin key already exists')
        return

    # Insert bin key before duplicateManager
    new_data = {}
    for key, val in data.items():
        if key == 'duplicateManager':
            new_data['bin'] = translations
        new_data[key] = val

    # If duplicateManager wasn't found, just append
    if 'bin' not in new_data:
        new_data['bin'] = translations

    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(new_data, f, ensure_ascii=False, indent=2)
        f.write('\n')

    print(f'  OK  {locale_code}')

if __name__ == '__main__':
    # Skip 'en' as it was already updated manually
    for locale_code, translations in BIN_TRANSLATIONS.items():
        if locale_code == 'en':
            continue
        add_bin_keys(locale_code, translations)
    print('Done.')

