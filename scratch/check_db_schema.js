const apikey = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";
const supabaseUrl = "https://gilxxyvwqucwwwqaxosx.supabase.co";
const headers = {
    "apikey": apikey,
    "Authorization": `Bearer ${apikey}`,
    "Content-Type": "application/json"
};

async function checkSchema() {
    try {
        const res = await fetch(`${supabaseUrl}/rest/v1/?apikey=${apikey}`, {
            method: 'GET',
        });
        const schema = await res.json();
        console.log("Full PostgREST response:", schema);
    } catch (e) {
        console.log("Error checking schema:", e);
    }
}

checkSchema();
