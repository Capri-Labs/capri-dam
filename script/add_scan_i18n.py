#!/usr/bin/env python3
"""Add duplicate_manager.scan i18n keys to all locale files."""
import json

# Translations for each locale
SCAN_KEYS = {
    'en': {
        'title':        'Repository Scan',
        'subtitle':     'Scan the entire repository for existing duplicate assets',
        'description':  'The scan analyses all asset versions in the repository. Multiple versions of the same asset that share a checksum are NOT counted as duplicates — only different assets that share a checksum are flagged.',
        'triggerButton':'Run Full Scan',
        'autoQueued':   'Duplicate detection enabled — a full repository scan has been queued automatically.',
        'queued':       'Repository scan has been queued.',
        'alreadyRunning':'A scan is already running. Please wait for it to finish.',
        'lastScan':     'Last scan completed',
        'versionNote':  'Versions of the same asset sharing a checksum are NOT duplicates.',
        'idle':         'Idle',
        'queued_s':     'Queued',
        'running':      'Running',
        'completed':    'Completed',
        'failed':       'Failed',
        'progressLabel':'{{processed}} of {{total}} checksums processed',
    },
    'de': {
        'title':        'Repository-Scan',
        'subtitle':     'Gesamtes Repository nach doppelten Assets durchsuchen',
        'description':  'Der Scan analysiert alle Asset-Versionen im Repository. Mehrere Versionen desselben Assets mit gleichem Prüfwert sind KEINE Duplikate — nur unterschiedliche Assets mit gleichem SHA-256 werden markiert.',
        'triggerButton':'Vollständigen Scan starten',
        'autoQueued':   'Duplikaterkennung aktiviert — ein vollständiger Repository-Scan wurde automatisch in die Warteschlange gestellt.',
        'queued':       'Repository-Scan wurde in die Warteschlange gestellt.',
        'alreadyRunning':'Ein Scan läuft bereits. Bitte warten Sie, bis er abgeschlossen ist.',
        'lastScan':     'Letzter Scan abgeschlossen',
        'versionNote':  'Versionen desselben Assets mit gleichem Prüfwert sind KEINE Duplikate.',
        'idle':         'Inaktiv',
        'queued_s':     'In der Warteschlange',
        'running':      'Wird ausgeführt',
        'completed':    'Abgeschlossen',
        'failed':       'Fehlgeschlagen',
        'progressLabel':'{{processed}} von {{total}} Prüfwerten verarbeitet',
    },
    'fr': {
        'title':        'Analyse du dépôt',
        'subtitle':     'Analyser tout le dépôt pour trouver les assets dupliqués',
        'description':  "L'analyse examine toutes les versions d'assets. Plusieurs versions du même asset partageant un checksum ne sont PAS des doublons — seuls les assets différents partageant un SHA-256 sont signalés.",
        'triggerButton':'Lancer l\'analyse complète',
        'autoQueued':   'Détection de doublons activée — une analyse complète du dépôt a été mise en file d\'attente automatiquement.',
        'queued':       'L\'analyse du dépôt a été mise en file d\'attente.',
        'alreadyRunning':'Une analyse est déjà en cours. Veuillez attendre qu\'elle se termine.',
        'lastScan':     'Dernière analyse terminée',
        'versionNote':  "Les versions du même asset partageant un checksum ne sont PAS des doublons.",
        'idle':         'Inactif',
        'queued_s':     'En file d\'attente',
        'running':      'En cours',
        'completed':    'Terminé',
        'failed':       'Échoué',
        'progressLabel':'{{processed}} sur {{total}} checksums traités',
    },
    'es': {
        'title':        'Análisis del repositorio',
        'subtitle':     'Analizar todo el repositorio para encontrar activos duplicados',
        'description':  'El análisis examina todas las versiones de activos. Varias versiones del mismo activo que comparten un checksum NO son duplicados — solo se marcan diferentes activos que comparten un SHA-256.',
        'triggerButton':'Ejecutar análisis completo',
        'autoQueued':   'Detección de duplicados activada — se ha puesto en cola un análisis completo del repositorio automáticamente.',
        'queued':       'El análisis del repositorio ha sido puesto en cola.',
        'alreadyRunning':'Ya hay un análisis en curso. Por favor, espere a que finalice.',
        'lastScan':     'Último análisis completado',
        'versionNote':  'Las versiones del mismo activo que comparten un checksum NO son duplicados.',
        'idle':         'Inactivo',
        'queued_s':     'En cola',
        'running':      'En ejecución',
        'completed':    'Completado',
        'failed':       'Fallido',
        'progressLabel':'{{processed}} de {{total}} checksums procesados',
    },
    'ja': {
        'title':        'リポジトリスキャン',
        'subtitle':     'リポジトリ全体で既存の重複アセットをスキャン',
        'description':  'スキャンはすべてのアセットバージョンを分析します。同じチェックサムを持つ同一アセットの複数バージョンは重複ではありません — 異なるアセットが同じSHA-256を共有している場合のみフラグが立てられます。',
        'triggerButton':'フルスキャンを実行',
        'autoQueued':   '重複検出が有効化されました — リポジトリの完全スキャンが自動的にキューに追加されました。',
        'queued':       'リポジトリスキャンがキューに追加されました。',
        'alreadyRunning':'スキャンはすでに実行中です。完了するまでお待ちください。',
        'lastScan':     '最終スキャン完了',
        'versionNote':  '同じチェックサムを共有する同一アセットのバージョンは重複ではありません。',
        'idle':         'アイドル',
        'queued_s':     'キュー済み',
        'running':      '実行中',
        'completed':    '完了',
        'failed':       '失敗',
        'progressLabel':'{{total}}件中{{processed}}件のチェックサムを処理済み',
    },
    'ko': {
        'title':        '저장소 스캔',
        'subtitle':     '전체 저장소에서 기존 중복 자산 스캔',
        'description':  '스캔은 모든 자산 버전을 분석합니다. 동일한 체크섬을 공유하는 같은 자산의 여러 버전은 중복이 아닙니다 — SHA-256을 공유하는 서로 다른 자산만 표시됩니다.',
        'triggerButton':'전체 스캔 실행',
        'autoQueued':   '중복 감지가 활성화되었습니다 — 전체 저장소 스캔이 자동으로 대기열에 추가되었습니다.',
        'queued':       '저장소 스캔이 대기열에 추가되었습니다.',
        'alreadyRunning':'스캔이 이미 실행 중입니다. 완료될 때까지 기다려 주세요.',
        'lastScan':     '마지막 스캔 완료',
        'versionNote':  '동일한 체크섬을 공유하는 같은 자산의 버전은 중복이 아닙니다.',
        'idle':         '유휴',
        'queued_s':     '대기 중',
        'running':      '실행 중',
        'completed':    '완료됨',
        'failed':       '실패',
        'progressLabel':'{{total}}개 중 {{processed}}개 체크섬 처리됨',
    },
    'nl': {
        'title':        'Repository-scan',
        'subtitle':     'Volledige repository scannen op dubbele assets',
        'description':  'De scan analyseert alle assetversies. Meerdere versies van hetzelfde asset met dezelfde checksum zijn GEEN duplicaten — alleen verschillende assets die een SHA-256 delen worden gemarkeerd.',
        'triggerButton':'Volledige scan uitvoeren',
        'autoQueued':   'Dubbele detectie ingeschakeld — een volledige repository-scan is automatisch in de wachtrij geplaatst.',
        'queued':       'Repository-scan staat in de wachtrij.',
        'alreadyRunning':'Er is al een scan actief. Wacht tot deze klaar is.',
        'lastScan':     'Laatste scan voltooid',
        'versionNote':  'Versies van hetzelfde asset met dezelfde checksum zijn GEEN duplicaten.',
        'idle':         'Inactief',
        'queued_s':     'In wachtrij',
        'running':      'Bezig',
        'completed':    'Voltooid',
        'failed':       'Mislukt',
        'progressLabel':'{{processed}} van {{total}} checksums verwerkt',
    },
    'pt': {
        'title':        'Varredura do repositório',
        'subtitle':     'Varrer todo o repositório em busca de ativos duplicados',
        'description':  'A varredura analisa todas as versões de ativos. Várias versões do mesmo ativo que compartilham um checksum NÃO são duplicatas — apenas ativos diferentes que compartilham um SHA-256 são sinalizados.',
        'triggerButton':'Executar varredura completa',
        'autoQueued':   'Detecção de duplicatas ativada — uma varredura completa do repositório foi enfileirada automaticamente.',
        'queued':       'A varredura do repositório foi enfileirada.',
        'alreadyRunning':'Uma varredura já está em andamento. Aguarde a conclusão.',
        'lastScan':     'Última varredura concluída',
        'versionNote':  'Versões do mesmo ativo que compartilham um checksum NÃO são duplicatas.',
        'idle':         'Ocioso',
        'queued_s':     'Na fila',
        'running':      'Em execução',
        'completed':    'Concluído',
        'failed':       'Falhou',
        'progressLabel':'{{processed}} de {{total}} checksums processados',
    },
    'zh': {
        'title':        '存储库扫描',
        'subtitle':     '扫描整个存储库以查找现有重复资产',
        'description':  '扫描分析所有资产版本。共享相同校验和的同一资产的多个版本不是重复项 — 只有共享相同 SHA-256 的不同资产才会被标记。',
        'triggerButton':'运行完整扫描',
        'autoQueued':   '重复检测已启用 — 完整存储库扫描已自动加入队列。',
        'queued':       '存储库扫描已加入队列。',
        'alreadyRunning':'扫描已在运行中。请等待其完成。',
        'lastScan':     '上次扫描完成',
        'versionNote':  '共享校验和的同一资产的版本不是重复项。',
        'idle':         '空闲',
        'queued_s':     '已排队',
        'running':      '运行中',
        'completed':    '已完成',
        'failed':       '失败',
        'progressLabel':'已处理 {{total}} 个校验和中的 {{processed}} 个',
    },
}


def build_scan_block(d):
    return {
        "title":         d['title'],
        "subtitle":      d['subtitle'],
        "description":   d['description'],
        "triggerButton": d['triggerButton'],
        "autoQueued":    d['autoQueued'],
        "queued":        d['queued'],
        "alreadyRunning":d['alreadyRunning'],
        "lastScan":      d['lastScan'],
        "versionNote":   d['versionNote'],
        "progressLabel": d['progressLabel'],
        "status": {
            "idle":      d['idle'],
            "queued":    d['queued_s'],
            "running":   d['running'],
            "completed": d['completed'],
            "failed":    d['failed'],
        }
    }


locale_dir = 'app/javascript/i18n/locales'

for lang, data in SCAN_KEYS.items():
    path = f'{locale_dir}/{lang}.json'
    with open(path, 'r', encoding='utf-8') as f:
        obj = json.load(f)

    # Ensure duplicateManager.scan exists
    if 'duplicateManager' not in obj:
        obj['duplicateManager'] = {}
    obj['duplicateManager']['scan'] = build_scan_block(data)

    with open(path, 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
    print(f'Updated {lang}.json — duplicateManager.scan added')

print('Done')

