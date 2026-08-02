const apikey = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";
const supabaseUrl = "https://gilxxyvwqucwwwqaxosx.supabase.co";
const headers = {
    "apikey": apikey,
    "Authorization": `Bearer ${apikey}`,
    "Content-Type": "application/json"
};

async function getAssociations() {
    try {
        console.log("--- Fetching user gym associations ---");
        const res = await fetch(`${supabaseUrl}/rest/v1/user_gym_associations`, { headers });
        const data = await res.json();
        console.log("Associations:", JSON.stringify(data, null, 2));
    } catch(e) {
        console.log("Error:", e);
    }
}

getAssociations();
