#!/usr/bin/env python3
"""Add bin.settings, bin.ai, bin.activePurge, and purge trigger i18n keys to all locales."""
import json, os

BASE = os.path.dirname(os.path.abspath(__file__))
LOCALES_DIR = os.path.join(BASE, '../app/javascript/i18n/locales')

# Extra keys nested under bin.* and bin.purge.*
DATA = {
    'en': {
        'settings': {
            'title': 'Recycle Bin & Purge',
            'subtitle': 'Configure how and when deleted assets are permanently removed.',
            'warningNote': 'Purging permanently deletes assets and all their versions from storage. This cannot be undone.',
            'policySubtitle': 'Items older than {{days}} days are purged · Workflow: {{behavior}}',
            'nextScheduled': 'Next scheduled run',
        },
        'activePurge': {
            'runningTitle': 'Recycle Bin purge in progress',
            'queuedTitle': 'Recycle Bin purge queued',
            'hint': 'Expired items are being permanently removed. This page will refresh when complete.',
        },
        'ai': {
            'title': 'AI-Assisted Cleanup',
            'comingSoon': 'Coming Soon',
            'description': 'Once connected to the Capri AI Gateway, the bin will gain intelligent cleanup capabilities:',
            'feature1': 'Smart suggestions for safe-to-delete assets based on usage, age & duplication.',
            'feature2': 'Risk scoring to flag assets that may still be needed before purging.',
            'feature3': 'Natural-language cleanup reports summarising what was removed and storage reclaimed.',
        },
        'purge_extra': {
            'triggeredBy': 'Triggered by {{name}}',
            'triggeredBySchedule': 'Triggered by the nightly schedule',
        },
    },
    'de': {
        'settings': {
            'title': 'Papierkorb & Bereinigung',
            'subtitle': 'Konfigurieren Sie, wie und wann gelöschte Assets dauerhaft entfernt werden.',
            'warningNote': 'Die Bereinigung löscht Assets und alle ihre Versionen dauerhaft aus dem Speicher. Dies kann nicht rückgängig gemacht werden.',
            'policySubtitle': 'Elemente älter als {{days}} Tage werden bereinigt · Workflow: {{behavior}}',
            'nextScheduled': 'Nächster geplanter Lauf',
        },
        'activePurge': {
            'runningTitle': 'Papierkorb-Bereinigung läuft',
            'queuedTitle': 'Papierkorb-Bereinigung in Warteschlange',
            'hint': 'Abgelaufene Elemente werden dauerhaft entfernt. Diese Seite wird nach Abschluss aktualisiert.',
        },
        'ai': {
            'title': 'KI-gestützte Bereinigung',
            'comingSoon': 'Demnächst',
            'description': 'Nach Verbindung mit dem Capri AI Gateway erhält der Papierkorb intelligente Funktionen:',
            'feature1': 'Intelligente Vorschläge für sicher löschbare Assets basierend auf Nutzung, Alter & Duplikaten.',
            'feature2': 'Risikobewertung zur Kennzeichnung möglicherweise noch benötigter Assets.',
            'feature3': 'Bereinigungsberichte in natürlicher Sprache.',
        },
        'purge_extra': {
            'triggeredBy': 'Ausgelöst von {{name}}',
            'triggeredBySchedule': 'Vom nächtlichen Zeitplan ausgelöst',
        },
    },
    'fr': {
        'settings': {
            'title': 'Corbeille et purge',
            'subtitle': 'Configurez comment et quand les assets supprimés sont définitivement retirés.',
            'warningNote': 'La purge supprime définitivement les assets et toutes leurs versions du stockage. Irréversible.',
            'policySubtitle': 'Éléments de plus de {{days}} jours purgés · Workflow : {{behavior}}',
            'nextScheduled': 'Prochaine exécution planifiée',
        },
        'activePurge': {
            'runningTitle': 'Purge de la corbeille en cours',
            'queuedTitle': 'Purge de la corbeille en file d\'attente',
            'hint': 'Les éléments expirés sont définitivement supprimés. La page se rafraîchira une fois terminé.',
        },
        'ai': {
            'title': 'Nettoyage assisté par IA',
            'comingSoon': 'Bientôt',
            'description': 'Une fois connectée au Capri AI Gateway, la corbeille gagnera des capacités intelligentes :',
            'feature1': 'Suggestions intelligentes d\'assets supprimables selon usage, âge et duplication.',
            'feature2': 'Score de risque pour signaler les assets potentiellement encore nécessaires.',
            'feature3': 'Rapports de nettoyage en langage naturel.',
        },
        'purge_extra': {
            'triggeredBy': 'Déclenché par {{name}}',
            'triggeredBySchedule': 'Déclenché par la planification nocturne',
        },
    },
    'es': {
        'settings': {
            'title': 'Papelera y purga',
            'subtitle': 'Configure cómo y cuándo se eliminan permanentemente los assets borrados.',
            'warningNote': 'La purga elimina permanentemente los assets y todas sus versiones del almacenamiento. No se puede deshacer.',
            'policySubtitle': 'Elementos de más de {{days}} días se purgan · Workflow: {{behavior}}',
            'nextScheduled': 'Próxima ejecución programada',
        },
        'activePurge': {
            'runningTitle': 'Purga de papelera en curso',
            'queuedTitle': 'Purga de papelera en cola',
            'hint': 'Los elementos expirados se están eliminando permanentemente. Esta página se actualizará al completarse.',
        },
        'ai': {
            'title': 'Limpieza asistida por IA',
            'comingSoon': 'Próximamente',
            'description': 'Al conectarse con Capri AI Gateway, la papelera obtendrá capacidades inteligentes:',
            'feature1': 'Sugerencias inteligentes de assets eliminables según uso, antigüedad y duplicación.',
            'feature2': 'Puntuación de riesgo para marcar assets que aún podrían necesitarse.',
            'feature3': 'Informes de limpieza en lenguaje natural.',
        },
        'purge_extra': {
            'triggeredBy': 'Activado por {{name}}',
            'triggeredBySchedule': 'Activado por la programación nocturna',
        },
    },
    'ja': {
        'settings': {
            'title': 'ゴミ箱とパージ',
            'subtitle': '削除されたアセットを永久に削除する方法とタイミングを設定します。',
            'warningNote': 'パージはアセットとそのすべてのバージョンをストレージから永久に削除します。元に戻せません。',
            'policySubtitle': '{{days}}日以上経過した項目をパージ · ワークフロー: {{behavior}}',
            'nextScheduled': '次回の予定実行',
        },
        'activePurge': {
            'runningTitle': 'ゴミ箱のパージを実行中',
            'queuedTitle': 'ゴミ箱のパージがキューに登録されました',
            'hint': '期限切れの項目を永久に削除しています。完了するとこのページが更新されます。',
        },
        'ai': {
            'title': 'AI支援クリーンアップ',
            'comingSoon': '近日公開',
            'description': 'Capri AI Gatewayに接続すると、ゴミ箱にインテリジェントな機能が追加されます:',
            'feature1': '使用状況、経過時間、重複に基づく安全に削除可能なアセットのスマート提案。',
            'feature2': 'まだ必要な可能性のあるアセットにフラグを立てるリスクスコアリング。',
            'feature3': '削除内容と回収ストレージを要約する自然言語クリーンアップレポート。',
        },
        'purge_extra': {
            'triggeredBy': '{{name}}によって実行',
            'triggeredBySchedule': '夜間スケジュールによって実行',
        },
    },
    'ko': {
        'settings': {
            'title': '휴지통 및 영구 삭제',
            'subtitle': '삭제된 에셋을 영구적으로 제거하는 방법과 시기를 구성합니다.',
            'warningNote': '영구 삭제는 에셋과 모든 버전을 스토리지에서 영구적으로 삭제합니다. 되돌릴 수 없습니다.',
            'policySubtitle': '{{days}}일이 지난 항목 제거 · 워크플로우: {{behavior}}',
            'nextScheduled': '다음 예약 실행',
        },
        'activePurge': {
            'runningTitle': '휴지통 영구 삭제 진행 중',
            'queuedTitle': '휴지통 영구 삭제 대기 중',
            'hint': '만료된 항목을 영구적으로 제거하고 있습니다. 완료되면 이 페이지가 새로 고침됩니다.',
        },
        'ai': {
            'title': 'AI 지원 정리',
            'comingSoon': '곧 출시',
            'description': 'Capri AI Gateway에 연결되면 휴지통에 지능형 정리 기능이 추가됩니다:',
            'feature1': '사용량, 기간, 중복을 기반으로 안전하게 삭제 가능한 에셋 스마트 제안.',
            'feature2': '아직 필요할 수 있는 에셋을 표시하는 위험 점수.',
            'feature3': '제거된 항목과 회수된 스토리지를 요약하는 자연어 정리 보고서.',
        },
        'purge_extra': {
            'triggeredBy': '{{name}}이(가) 실행',
            'triggeredBySchedule': '야간 일정에 의해 실행',
        },
    },
    'nl': {
        'settings': {
            'title': 'Prullenbak & opschoning',
            'subtitle': 'Configureer hoe en wanneer verwijderde assets definitief worden verwijderd.',
            'warningNote': 'Opschonen verwijdert assets en al hun versies definitief uit de opslag. Dit kan niet ongedaan worden gemaakt.',
            'policySubtitle': 'Items ouder dan {{days}} dagen worden opgeschoond · Workflow: {{behavior}}',
            'nextScheduled': 'Volgende geplande uitvoering',
        },
        'activePurge': {
            'runningTitle': 'Prullenbak opschoning bezig',
            'queuedTitle': 'Prullenbak opschoning in wachtrij',
            'hint': 'Verlopen items worden definitief verwijderd. Deze pagina wordt vernieuwd wanneer voltooid.',
        },
        'ai': {
            'title': 'AI-ondersteunde opschoning',
            'comingSoon': 'Binnenkort',
            'description': 'Eenmaal verbonden met de Capri AI Gateway krijgt de prullenbak intelligente mogelijkheden:',
            'feature1': 'Slimme suggesties voor veilig te verwijderen assets op basis van gebruik, leeftijd & duplicatie.',
            'feature2': 'Risicoscores om assets te markeren die mogelijk nog nodig zijn.',
            'feature3': 'Opschoningsrapporten in natuurlijke taal.',
        },
        'purge_extra': {
            'triggeredBy': 'Gestart door {{name}}',
            'triggeredBySchedule': 'Gestart door de nachtelijke planning',
        },
    },
    'pt': {
        'settings': {
            'title': 'Lixeira e limpeza',
            'subtitle': 'Configure como e quando os assets excluídos são removidos permanentemente.',
            'warningNote': 'A limpeza exclui permanentemente os assets e todas as suas versões do armazenamento. Não pode ser desfeito.',
            'policySubtitle': 'Itens com mais de {{days}} dias são removidos · Workflow: {{behavior}}',
            'nextScheduled': 'Próxima execução agendada',
        },
        'activePurge': {
            'runningTitle': 'Limpeza da lixeira em andamento',
            'queuedTitle': 'Limpeza da lixeira na fila',
            'hint': 'Itens expirados estão sendo removidos permanentemente. Esta página será atualizada quando concluída.',
        },
        'ai': {
            'title': 'Limpeza assistida por IA',
            'comingSoon': 'Em breve',
            'description': 'Após conectar ao Capri AI Gateway, a lixeira ganhará recursos inteligentes:',
            'feature1': 'Sugestões inteligentes de assets removíveis com base em uso, idade e duplicação.',
            'feature2': 'Pontuação de risco para sinalizar assets que ainda podem ser necessários.',
            'feature3': 'Relatórios de limpeza em linguagem natural.',
        },
        'purge_extra': {
            'triggeredBy': 'Acionado por {{name}}',
            'triggeredBySchedule': 'Acionado pelo agendamento noturno',
        },
    },
    'zh': {
        'settings': {
            'title': '回收站与清除',
            'subtitle': '配置删除资源的永久移除方式和时间。',
            'warningNote': '清除会从存储中永久删除资源及其所有版本。此操作无法撤销。',
            'policySubtitle': '超过 {{days}} 天的项目将被清除 · 工作流：{{behavior}}',
            'nextScheduled': '下次计划运行',
        },
        'activePurge': {
            'runningTitle': '回收站清除进行中',
            'queuedTitle': '回收站清除已排队',
            'hint': '正在永久删除过期项目。完成后此页面将刷新。',
        },
        'ai': {
            'title': 'AI 辅助清理',
            'comingSoon': '即将推出',
            'description': '连接 Capri AI Gateway 后，回收站将获得智能清理功能：',
            'feature1': '基于使用情况、时长和重复性的安全删除资源智能建议。',
            'feature2': '风险评分以标记可能仍需要的资源。',
            'feature3': '总结已删除内容和回收存储的自然语言清理报告。',
        },
        'purge_extra': {
            'triggeredBy': '由 {{name}} 触发',
            'triggeredBySchedule': '由夜间计划触发',
        },
    },
}

for locale, blocks in DATA.items():
    path = os.path.join(LOCALES_DIR, f'{locale}.json')
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    data.setdefault('bin', {})
    data['bin']['settings']    = blocks['settings']
    data['bin']['activePurge'] = blocks['activePurge']
    data['bin']['ai']          = blocks['ai']

    # Merge the two extra purge keys into the existing bin.purge object
    data['bin'].setdefault('purge', {})
    data['bin']['purge']['triggeredBy']         = blocks['purge_extra']['triggeredBy']
    data['bin']['purge']['triggeredBySchedule'] = blocks['purge_extra']['triggeredBySchedule']

    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print(f'  OK  {locale}')

print('Done.')

