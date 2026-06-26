#!/usr/bin/env python3
"""Add duplicate manager i18n keys to all locale files."""
import json

LOCALES = {
    'fr': {
        'tools': {
            'uploadRestrictions': 'Restrictions de téléversement',
            'uploadRestrictionsDesc': 'Gérer les types MIME autorisés',
            'imageProfiles': 'Profils image',
            'imageProfilesDesc': 'Recadrage automatique au téléversement',
            'videoProfiles': 'Profils vidéo',
            'videoProfilesDesc': 'Encodage vidéo adaptatif'
        },
        'common': {'refresh': 'Actualiser', 'confirm': 'Confirmer', 'cancel': 'Annuler', 'delete': 'Supprimer', 'close': 'Fermer', 'error': 'Erreur'},
        'dm': {
            'title': 'Gestionnaire de doublons',
            'subtitle': 'Vérifiez et résolvez les doublons détectés',
            'emptyState': 'Aucun doublon trouvé. Votre dépôt est propre !',
            'identicalFiles': '{{count}} fichiers identiques',
            'potentialMatch': 'Correspondance potentielle',
            'sha256': 'SHA-256',
            'resolutionTitle': 'Résoudre les doublons',
            'resolutionSubtitle': '{{count}} assets trouvés',
            'accept': 'Tout conserver',
            'delete': 'Supprimer la sélection',
            'dismiss': 'Ignorer',
            'navigateTo': "Aller à l'asset",
            'goToFolder': 'Aller au dossier',
            'originalBadge': 'Original — copie la plus ancienne',
            'selectedCount': '{{count}} sélectionné(s) pour suppression',
            'confirmDeleteBody': 'Les assets sélectionnés seront déplacés dans la corbeille.',
            'resolvedSuccess': 'Groupe de doublons résolu.',
            'keptAllSuccess': 'Tous les assets conservés.',
            'deletedSuccess': '{{count}} asset(s) déplacé(s) dans la corbeille.',
            'loading': 'Chargement des doublons…',
            'settingsTitle': 'Paramètres du gestionnaire de doublons',
            'settingsSubtitle': 'Configurer la détection de doublons',
            'enableLabel': 'Activer la détection de doublons',
            'enableHelp': 'Vérifie le SHA-256 de chaque asset téléversé.',
            'inboxLabel': 'Notifications Inbox',
            'inboxHelp': 'Envoie une notification agrégée si des doublons sont détectés.',
            'perfWarning': 'La détection peut affecter les performances de téléversement.',
            'maxReported': 'Les {{count}} premiers groupes sont affichés.',
            'saved': 'Paramètres sauvegardés.',
            'loadError': 'Échec du chargement.',
            'adminOnly': 'Admin seulement',
            'statusEnabled': 'Activé',
            'statusDisabled': 'Désactivé',
            'statusPending': 'En attente',
            'statusResolved': 'Résolu',
            'statusDismissed': 'Ignoré',
            'filterAll': 'Tous les groupes',
            'filterPending': 'En attente',
            'filterResolved': 'Résolu',
            'statTotal': 'Groupes au total',
            'statPending': 'En attente',
            'statResolved': 'Résolu'
        }
    },
    'es': {
        'tools': {
            'uploadRestrictions': 'Restricciones de carga',
            'uploadRestrictionsDesc': 'Gestionar tipos MIME permitidos',
            'imageProfiles': 'Perfiles de imagen',
            'imageProfilesDesc': 'Recorte automático al cargar',
            'videoProfiles': 'Perfiles de vídeo',
            'videoProfilesDesc': 'Codificación de vídeo adaptativa'
        },
        'common': {'refresh': 'Actualizar', 'confirm': 'Confirmar', 'cancel': 'Cancelar', 'delete': 'Eliminar', 'close': 'Cerrar', 'error': 'Error'},
        'dm': {
            'title': 'Gestor de duplicados',
            'subtitle': 'Revise y resuelva activos duplicados detectados',
            'emptyState': 'No se encontraron duplicados. Su repositorio está limpio!',
            'identicalFiles': '{{count}} archivos idénticos',
            'potentialMatch': 'Posible coincidencia',
            'sha256': 'SHA-256',
            'resolutionTitle': 'Resolver duplicados',
            'resolutionSubtitle': '{{count}} activos encontrados',
            'accept': 'Mantener todos',
            'delete': 'Eliminar seleccionados',
            'dismiss': 'Descartar sin acción',
            'navigateTo': 'Ir al activo',
            'goToFolder': 'Ir a la carpeta',
            'originalBadge': 'Original — copia más antigua',
            'selectedCount': '{{count}} seleccionados para eliminar',
            'confirmDeleteBody': 'Los activos seleccionados se moverán a la papelera.',
            'resolvedSuccess': 'Grupo de duplicados resuelto.',
            'keptAllSuccess': 'Todos los activos conservados.',
            'deletedSuccess': '{{count}} activo(s) movido(s) a la papelera.',
            'loading': 'Cargando duplicados...',
            'settingsTitle': 'Configuración del gestor de duplicados',
            'settingsSubtitle': 'Configurar la detección de duplicados',
            'enableLabel': 'Activar detección de duplicados',
            'enableHelp': 'Verifica el SHA-256 de cada activo cargado.',
            'inboxLabel': 'Notificaciones en bandeja',
            'inboxHelp': 'Envía notificación agregada cuando se detectan duplicados.',
            'perfWarning': 'La detección puede afectar el rendimiento de carga.',
            'maxReported': 'Se muestran los primeros {{count}} grupos.',
            'saved': 'Configuración guardada.',
            'loadError': 'Error al cargar la configuración.',
            'adminOnly': 'Solo administradores',
            'statusEnabled': 'Activado',
            'statusDisabled': 'Desactivado',
            'statusPending': 'Pendiente',
            'statusResolved': 'Resuelto',
            'statusDismissed': 'Descartado',
            'filterAll': 'Todos los grupos',
            'filterPending': 'Pendiente',
            'filterResolved': 'Resuelto',
            'statTotal': 'Total de grupos',
            'statPending': 'Pendiente',
            'statResolved': 'Resuelto'
        }
    },
    'ja': {
        'tools': {
            'uploadRestrictions': 'アップロード制限',
            'uploadRestrictionsDesc': '許可されるMIMEタイプを管理',
            'imageProfiles': '画像プロファイル',
            'imageProfilesDesc': 'アップロード時の自動クロップ',
            'videoProfiles': 'ビデオプロファイル',
            'videoProfilesDesc': 'アダプティブビデオエンコード'
        },
        'common': {'refresh': '更新', 'confirm': '確認', 'cancel': 'キャンセル', 'delete': '削除', 'close': '閉じる', 'error': 'エラー'},
        'dm': {
            'title': '重複マネージャー',
            'subtitle': '検出された重複アセットを確認・解決',
            'emptyState': '重複グループが見つかりません。リポジトリはクリーンです！',
            'identicalFiles': '{{count}} 個の同一ファイル',
            'potentialMatch': '潜在的な一致',
            'sha256': 'SHA-256',
            'resolutionTitle': '重複を解決',
            'resolutionSubtitle': '{{count}} 個のアセットが見つかりました',
            'accept': 'すべて保持',
            'delete': '選択を削除',
            'dismiss': 'アクションなしで閉じる',
            'navigateTo': 'アセットに移動',
            'goToFolder': 'フォルダに移動',
            'originalBadge': 'オリジナル — 最古のコピー',
            'selectedCount': '{{count}} 個が削除対象として選択済み',
            'confirmDeleteBody': '選択されたアセットはごみ箱に移動されます。',
            'resolvedSuccess': '重複グループが解決されました。',
            'keptAllSuccess': 'すべてのアセットを保持しました。',
            'deletedSuccess': '{{count}} 個のアセットをごみ箱に移動しました。',
            'loading': '重複を読み込み中…',
            'settingsTitle': '重複マネージャー設定',
            'settingsSubtitle': 'アップロード時の重複検出を設定',
            'enableLabel': '重複検出を有効化',
            'enableHelp': 'アップロードされた各アセットのSHA-256チェックサムを確認します。',
            'inboxLabel': '受信トレイ通知',
            'inboxHelp': '重複が検出された場合に集約通知を送信します。',
            'perfWarning': '重複検出はアップロードのパフォーマンスに影響する場合があります。',
            'maxReported': '最初の{{count}}グループが表示されます。',
            'saved': '設定を保存しました。',
            'loadError': '設定の読み込みに失敗しました。',
            'adminOnly': '管理者のみ',
            'statusEnabled': '有効',
            'statusDisabled': '無効',
            'statusPending': '保留中',
            'statusResolved': '解決済み',
            'statusDismissed': '却下済み',
            'filterAll': 'すべてのグループ',
            'filterPending': '保留中',
            'filterResolved': '解決済み',
            'statTotal': 'グループ合計',
            'statPending': '保留中',
            'statResolved': '解決済み'
        }
    },
    'ko': {
        'tools': {
            'uploadRestrictions': '업로드 제한',
            'uploadRestrictionsDesc': '허용 MIME 유형 관리',
            'imageProfiles': '이미지 프로파일',
            'imageProfilesDesc': '업로드 시 자동 자르기',
            'videoProfiles': '비디오 프로파일',
            'videoProfilesDesc': '적응형 비디오 인코딩'
        },
        'common': {'refresh': '새로 고침', 'confirm': '확인', 'cancel': '취소', 'delete': '삭제', 'close': '닫기', 'error': '오류'},
        'dm': {
            'title': '중복 관리자',
            'subtitle': '감지된 중복 자산 검토 및 해결',
            'emptyState': '중복 그룹이 없습니다. 저장소가 깨끗합니다!',
            'identicalFiles': '동일한 파일 {{count}}개',
            'potentialMatch': '잠재적 일치',
            'sha256': 'SHA-256',
            'resolutionTitle': '중복 해결',
            'resolutionSubtitle': '{{count}}개 자산 발견',
            'accept': '모두 유지',
            'delete': '선택 항목 삭제',
            'dismiss': '작업 없이 닫기',
            'navigateTo': '자산으로 이동',
            'goToFolder': '폴더로 이동',
            'originalBadge': '원본 — 가장 오래된 사본',
            'selectedCount': '{{count}}개 삭제 선택됨',
            'confirmDeleteBody': '선택된 자산이 휴지통으로 이동됩니다.',
            'resolvedSuccess': '중복 그룹이 해결되었습니다.',
            'keptAllSuccess': '모든 자산을 유지했습니다.',
            'deletedSuccess': '{{count}}개 자산이 휴지통으로 이동되었습니다.',
            'loading': '중복 로딩 중...',
            'settingsTitle': '중복 관리자 설정',
            'settingsSubtitle': '자산 업로드 중복 감지 구성',
            'enableLabel': '중복 감지 활성화',
            'enableHelp': '업로드된 각 자산의 SHA-256 체크섬을 확인합니다.',
            'inboxLabel': '받은 편지함 알림',
            'inboxHelp': '중복 감지 시 집계 알림을 보냅니다.',
            'perfWarning': '중복 감지는 업로드 성능에 영향을 줄 수 있습니다.',
            'maxReported': '처음 {{count}}개 그룹이 표시됩니다.',
            'saved': '설정이 저장되었습니다.',
            'loadError': '설정을 불러오지 못했습니다.',
            'adminOnly': '관리자 전용',
            'statusEnabled': '활성화됨',
            'statusDisabled': '비활성화됨',
            'statusPending': '보류 중',
            'statusResolved': '해결됨',
            'statusDismissed': '무시됨',
            'filterAll': '모든 그룹',
            'filterPending': '보류 중',
            'filterResolved': '해결됨',
            'statTotal': '전체 그룹',
            'statPending': '보류 중',
            'statResolved': '해결됨'
        }
    },
    'nl': {
        'tools': {
            'uploadRestrictions': 'Upload-restricties',
            'uploadRestrictionsDesc': 'Toegestane MIME-typen beheren',
            'imageProfiles': 'Beeldprofielen',
            'imageProfilesDesc': 'Automatisch bijsnijden bij upload',
            'videoProfiles': 'Videoprofielen',
            'videoProfilesDesc': 'Adaptieve videocodering'
        },
        'common': {'refresh': 'Vernieuwen', 'confirm': 'Bevestigen', 'cancel': 'Annuleren', 'delete': 'Verwijderen', 'close': 'Sluiten', 'error': 'Fout'},
        'dm': {
            'title': 'Dubbelbeheer',
            'subtitle': 'Gedetecteerde dubbele assets bekijken en oplossen',
            'emptyState': 'Geen dubbele groepen gevonden. Uw repository is schoon!',
            'identicalFiles': '{{count}} identieke bestanden',
            'potentialMatch': 'Mogelijke overeenkomst',
            'sha256': 'SHA-256',
            'resolutionTitle': 'Duplicaten oplossen',
            'resolutionSubtitle': '{{count}} assets gevonden',
            'accept': 'Alles bewaren',
            'delete': 'Geselecteerde verwijderen',
            'dismiss': 'Sluiten zonder actie',
            'navigateTo': 'Naar asset navigeren',
            'goToFolder': 'Naar map',
            'originalBadge': 'Origineel — oudste kopie',
            'selectedCount': '{{count}} geselecteerd voor verwijdering',
            'confirmDeleteBody': 'De geselecteerde assets worden naar de prullenbak verplaatst.',
            'resolvedSuccess': 'Dubbele groep opgelost.',
            'keptAllSuccess': 'Alle assets bewaard.',
            'deletedSuccess': '{{count}} asset(s) naar prullenbak verplaatst.',
            'loading': 'Duplicaten laden...',
            'settingsTitle': 'Dubbelbeheer-instellingen',
            'settingsSubtitle': 'Dubbele detectie voor asset-uploads configureren',
            'enableLabel': 'Dubbele detectie inschakelen',
            'enableHelp': 'Controleert de SHA-256 van elk geüpload asset.',
            'inboxLabel': 'Inbox-meldingen',
            'inboxHelp': 'Stuurt een geaggregeerde melding als duplicaten worden gedetecteerd.',
            'perfWarning': 'Detectie kan de uploadprestaties beïnvloeden.',
            'maxReported': 'De eerste {{count}} groepen worden weergegeven.',
            'saved': 'Instellingen opgeslagen.',
            'loadError': 'Instellingen laden mislukt.',
            'adminOnly': 'Alleen beheerders',
            'statusEnabled': 'Ingeschakeld',
            'statusDisabled': 'Uitgeschakeld',
            'statusPending': 'In behandeling',
            'statusResolved': 'Opgelost',
            'statusDismissed': 'Afgewezen',
            'filterAll': 'Alle groepen',
            'filterPending': 'In behandeling',
            'filterResolved': 'Opgelost',
            'statTotal': 'Totaal groepen',
            'statPending': 'In behandeling',
            'statResolved': 'Opgelost'
        }
    },
    'pt': {
        'tools': {
            'uploadRestrictions': 'Restrições de upload',
            'uploadRestrictionsDesc': 'Gerenciar tipos MIME permitidos',
            'imageProfiles': 'Perfis de imagem',
            'imageProfilesDesc': 'Corte automático ao carregar',
            'videoProfiles': 'Perfis de vídeo',
            'videoProfilesDesc': 'Codificação de vídeo adaptativa'
        },
        'common': {'refresh': 'Atualizar', 'confirm': 'Confirmar', 'cancel': 'Cancelar', 'delete': 'Excluir', 'close': 'Fechar', 'error': 'Erro'},
        'dm': {
            'title': 'Gerenciador de duplicatas',
            'subtitle': 'Revisar e resolver ativos duplicados detectados',
            'emptyState': 'Nenhum grupo de duplicatas encontrado. Seu repositório está limpo!',
            'identicalFiles': '{{count}} arquivos idênticos',
            'potentialMatch': 'Correspondência potencial',
            'sha256': 'SHA-256',
            'resolutionTitle': 'Resolver duplicatas',
            'resolutionSubtitle': '{{count}} ativos encontrados',
            'accept': 'Manter todos',
            'delete': 'Excluir selecionados',
            'dismiss': 'Fechar sem ação',
            'navigateTo': 'Navegar até o ativo',
            'goToFolder': 'Ir para a pasta',
            'originalBadge': 'Original — cópia mais antiga',
            'selectedCount': '{{count}} selecionado(s) para exclusão',
            'confirmDeleteBody': 'Os ativos selecionados serão movidos para a lixeira.',
            'resolvedSuccess': 'Grupo de duplicatas resolvido.',
            'keptAllSuccess': 'Todos os ativos mantidos.',
            'deletedSuccess': '{{count}} ativo(s) movido(s) para a lixeira.',
            'loading': 'Carregando duplicatas...',
            'settingsTitle': 'Configurações do gerenciador de duplicatas',
            'settingsSubtitle': 'Configurar detecção de duplicatas no upload',
            'enableLabel': 'Ativar detecção de duplicatas',
            'enableHelp': 'Verifica o SHA-256 de cada ativo carregado.',
            'inboxLabel': 'Notificações na caixa de entrada',
            'inboxHelp': 'Envia notificação agregada quando duplicatas são detectadas.',
            'perfWarning': 'A detecção pode afetar o desempenho de upload.',
            'maxReported': 'Os primeiros {{count}} grupos são exibidos.',
            'saved': 'Configurações salvas.',
            'loadError': 'Falha ao carregar configurações.',
            'adminOnly': 'Somente administradores',
            'statusEnabled': 'Ativado',
            'statusDisabled': 'Desativado',
            'statusPending': 'Pendente',
            'statusResolved': 'Resolvido',
            'statusDismissed': 'Ignorado',
            'filterAll': 'Todos os grupos',
            'filterPending': 'Pendente',
            'filterResolved': 'Resolvido',
            'statTotal': 'Total de grupos',
            'statPending': 'Pendente',
            'statResolved': 'Resolvido'
        }
    },
    'zh': {
        'tools': {
            'uploadRestrictions': '上传限制',
            'uploadRestrictionsDesc': '管理允许的 MIME 类型',
            'imageProfiles': '图像配置文件',
            'imageProfilesDesc': '上传时自动裁剪',
            'videoProfiles': '视频配置文件',
            'videoProfilesDesc': '自适应视频编码'
        },
        'common': {'refresh': '刷新', 'confirm': '确认', 'cancel': '取消', 'delete': '删除', 'close': '关闭', 'error': '错误'},
        'dm': {
            'title': '重复管理器',
            'subtitle': '查看并解决检测到的重复资产',
            'emptyState': '未找到重复组。您的存储库是干净的！',
            'identicalFiles': '{{count}} 个相同文件',
            'potentialMatch': '潜在匹配',
            'sha256': 'SHA-256',
            'resolutionTitle': '解决重复项',
            'resolutionSubtitle': '找到 {{count}} 个资产',
            'accept': '全部保留',
            'delete': '删除选中项',
            'dismiss': '不操作关闭',
            'navigateTo': '导航到资产',
            'goToFolder': '前往文件夹',
            'originalBadge': '原始 — 最早的副本',
            'selectedCount': '已选择 {{count}} 项待删除',
            'confirmDeleteBody': '选定的资产将被移至回收站。',
            'resolvedSuccess': '重复组已解决。',
            'keptAllSuccess': '已保留所有资产。',
            'deletedSuccess': '{{count}} 个资产已移至回收站。',
            'loading': '正在加载重复项...',
            'settingsTitle': '重复管理器设置',
            'settingsSubtitle': '配置资产上传的重复检测',
            'enableLabel': '启用重复检测',
            'enableHelp': '检查每个上传资产的 SHA-256 校验和。',
            'inboxLabel': '收件箱通知',
            'inboxHelp': '检测到重复时发送聚合通知。',
            'perfWarning': '重复检测可能影响上传性能。',
            'maxReported': '显示前 {{count}} 个重复组。',
            'saved': '设置已保存。',
            'loadError': '加载设置失败。',
            'adminOnly': '仅管理员',
            'statusEnabled': '已启用',
            'statusDisabled': '已禁用',
            'statusPending': '待处理',
            'statusResolved': '已解决',
            'statusDismissed': '已忽略',
            'filterAll': '所有组',
            'filterPending': '待处理',
            'filterResolved': '已解决',
            'statTotal': '组总数',
            'statPending': '待处理',
            'statResolved': '已解决'
        }
    }
}


def build_dm_block(d):
    return {
        "tools": {
            "assetConfigurations": {
                "uploadRestrictions": d['tools']['uploadRestrictions'],
                "uploadRestrictionsDesc": d['tools']['uploadRestrictionsDesc'],
                "imageProfiles": d['tools']['imageProfiles'],
                "imageProfilesDesc": d['tools']['imageProfilesDesc'],
                "videoProfiles": d['tools']['videoProfiles'],
                "videoProfilesDesc": d['tools']['videoProfilesDesc']
            }
        },
        "duplicateManager": {
            "title": d['dm']['title'],
            "subtitle": d['dm']['subtitle'],
            "emptyState": d['dm']['emptyState'],
            "group": {
                "identicalFiles": d['dm']['identicalFiles'],
                "potentialMatch": d['dm']['potentialMatch'],
                "sha256": d['dm']['sha256']
            },
            "resolution": {
                "title": d['dm']['resolutionTitle'],
                "subtitle": d['dm']['resolutionSubtitle'],
                "accept": d['dm']['accept'],
                "delete": d['dm']['delete'],
                "dismiss": d['dm']['dismiss'],
                "navigateTo": d['dm']['navigateTo'],
                "goToFolder": d['dm']['goToFolder'],
                "originalBadge": d['dm']['originalBadge'],
                "selectedCount": d['dm']['selectedCount'],
                "confirmDeleteBody": d['dm']['confirmDeleteBody'],
                "resolvedSuccess": d['dm']['resolvedSuccess'],
                "keptAllSuccess": d['dm']['keptAllSuccess'],
                "deletedSuccess": d['dm']['deletedSuccess'],
                "loading": d['dm']['loading']
            },
            "settings": {
                "title": d['dm']['settingsTitle'],
                "subtitle": d['dm']['settingsSubtitle'],
                "enableLabel": d['dm']['enableLabel'],
                "enableHelp": d['dm']['enableHelp'],
                "inboxNotificationsLabel": d['dm']['inboxLabel'],
                "inboxNotificationsHelp": d['dm']['inboxHelp'],
                "performanceWarning": d['dm']['perfWarning'],
                "maxReported": d['dm']['maxReported'],
                "saved": d['dm']['saved'],
                "loadError": d['dm']['loadError'],
                "adminOnly": d['dm']['adminOnly'],
                "status": {
                    "enabled": d['dm']['statusEnabled'],
                    "disabled": d['dm']['statusDisabled']
                }
            },
            "status": {
                "pending": d['dm']['statusPending'],
                "resolved": d['dm']['statusResolved'],
                "dismissed": d['dm']['statusDismissed']
            },
            "filters": {
                "all": d['dm']['filterAll'],
                "pending": d['dm']['filterPending'],
                "resolved": d['dm']['filterResolved']
            },
            "stats": {
                "totalGroups": d['dm']['statTotal'],
                "pendingGroups": d['dm']['statPending'],
                "resolvedGroups": d['dm']['statResolved']
            }
        }
    }


locale_dir = 'app/javascript/i18n/locales'

for lang, data in LOCALES.items():
    path = f'{locale_dir}/{lang}.json'
    with open(path, 'r', encoding='utf-8') as f:
        obj = json.load(f)

    extra = build_dm_block(data)
    obj['tools'] = extra['tools']
    # Add refresh key to common if it exists
    if 'common' not in obj:
        obj['common'] = {}
    obj['common']['refresh'] = data['common']['refresh']
    obj['duplicateManager'] = extra['duplicateManager']

    with open(path, 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
    print(f'Updated {lang}.json')

print('Done')

