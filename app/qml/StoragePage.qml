// What Telegram keeps on the phone (getStorageStatisticsFast), the cache emptied on asking
// (optimizeStorage: the files, not the chats), and what comes down by itself.
import QtQuick

SubPage {
    id: page
    title: "Ma'lumotlar va xotira"
    property var stats: null
    property string done: ""
    Component.onCompleted: refresh()
    function refresh() {
        store.send({ "@type": "getStorageStatisticsFast" }, (r) => {
            if (r["@type"] === "storageStatisticsFast")
                page.stats = r
        })
    }

    SettingsGroup {
        title: "Xotira"
        note: page.done || "Kesh — yuklangan rasm, video va fayllar. Tozalansa, kerak bo'lganda qayta yuklanadi; chatlar o'chmaydi."
        SettingsRow { text: "Fayllar (kesh)"; chevron: false; value: page.stats ? store.size(page.stats.files_size) + " · " + page.stats.file_count + " ta" : "..." }
        SettingsRow { text: "Ma'lumotlar bazasi"; chevron: false; value: page.stats ? store.size(page.stats.database_size) : "..." }
        SettingsRow {
            text: "Keshni tozalash"; chevron: false; last: true
            danger: true
            onClicked: {
                page.done = "Tozalanmoqda..."
                store.send({ "@type": "optimizeStorage", size: 0, ttl: 0, count: 0, immunity_delay: 0,
                             file_types: null, chat_ids: null, exclude_chat_ids: null,
                             return_deleted_file_statistics: false, chat_limit: 0 }, (r) => {
                    page.done = r["@type"] === "error" ? "Bo'lmadi: " + r.message : "Kesh tozalandi."
                    page.refresh()
                })
            }
        }
    }
    SettingsGroup {
        title: "O'zi yuklansin"
        note: "GIF va video-stikerlar; ovozli xabarlar va dumaloq videolar. O'chirilsa, bosilgandagina yuklanadi."
        SettingsRow { text: "GIF'lar o'zi o'ynasin"; toggle: true; on: Prefs.autoGif; onClicked: Prefs.autoGif = !Prefs.autoGif }
        SettingsRow { text: "Ovozli va dumaloq videolar"; toggle: true; on: Prefs.autoVoice; last: true; onClicked: Prefs.autoVoice = !Prefs.autoVoice }
    }
}
