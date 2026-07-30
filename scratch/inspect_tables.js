const apikey = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";
const supabaseUrl = "https://gilxxyvwqucwwwqaxosx.supabase.co";
const headers = {
    "apikey": apikey,
    "Authorization": `Bearer ${apikey}`,
    "Content-Type": "application/json"
};

async function checkCurrentFunction() {
    // Check what the current process_qr_attendance function signature looks like
    // by calling it with known bad params to see the error
    console.log("--- Check existing function signatures ---");
    
    // Try calling with just p_token
    try {
        const res = await fetch(`${supabaseUrl}/rest/v1/rpc/process_qr_attendance`, {
            method: 'POST',
            headers,
            body: JSON.stringify({ p_token: 'test_invalid_token' })
        });
        const data = await res.json();
        console.log("Call with p_token only:", JSON.stringify(data));
    } catch(e) {
        console.log("Error:", e.message);
    }

    // Try calling with p_token and p_user_type
    try {
        const res = await fetch(`${supabaseUrl}/rest/v1/rpc/process_qr_attendance`, {
            method: 'POST',
            headers,
            body: JSON.stringify({ p_token: 'test_invalid_token', p_user_type: 'Member' })
        });
        const data = await res.json();
        console.log("Call with p_token + p_user_type:", JSON.stringify(data));
    } catch(e) {
        console.log("Error:", e.message);
    }
}

checkCurrentFunction();
