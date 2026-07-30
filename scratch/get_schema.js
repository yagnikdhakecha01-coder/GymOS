const apikey = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";
const url = "https://gilxxyvwqucwwwqaxosx.supabase.co/rest/v1/";

const headers = {
    "apikey": apikey,
    "Authorization": `Bearer ${apikey}`,
    "Content-Type": "application/json"
};

fetch(url, { headers })
.then(r => r.json())
.then(schema => {
    console.log(schema);
})
.catch(err => {
    console.error("Failed:", err);
});
