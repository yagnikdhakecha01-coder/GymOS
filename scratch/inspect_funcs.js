const apikey = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";
const supabaseUrl = "https://gilxxyvwqucwwwqaxosx.supabase.co";
const headers = {
    "apikey": apikey,
    "Authorization": `Bearer ${apikey}`,
    "Content-Type": "application/json"
};

async function checkFunctions() {
    // Check what RPC functions are available related to attendance, shifts, leave
    const url = `${supabaseUrl}/rest/v1/`;
    try {
        const res = await fetch(url, { headers });
        const data = await res.json();
        
        console.log("Functions available:");
        const paths = Object.keys(data.paths || {}).filter(p => p.includes('rpc'));
        const attFuncs = paths.filter(p => p.includes('attendance') || p.includes('absent') || p.includes('leave') || p.includes('daily'));
        console.log(attFuncs);
    } catch(e) {
        console.log("Error:", e.message);
    }
}

checkFunctions();
