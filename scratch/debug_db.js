const urlSettings = "https://gilxxyvwqucwwwqaxosx.supabase.co/rest/v1/attendance_settings";
const apikey = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";

const headers = {
    "apikey": apikey,
    "Authorization": `Bearer ${apikey}`,
    "Content-Type": "application/json"
};

console.log("Querying attendance settings...");

fetch(urlSettings, { headers })
.then(r => r.json())
.then(data => {
    console.log(JSON.stringify(data, null, 2));
})
.catch(err => {
    console.error("Failed to query settings:", err);
});
