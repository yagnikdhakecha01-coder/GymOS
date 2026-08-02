const apikey = "sb_publishable_EId-4nC0kB8MG9omaGCTIA_EuAoJ3WP";
const supabaseUrl = "https://gilxxyvwqucwwwqaxosx.supabase.co";
const headers = {
    "apikey": apikey,
    "Authorization": `Bearer ${apikey}`,
    "Content-Type": "application/json",
    "Prefer": "return=representation"
};

async function testInsert() {
    const url = `${supabaseUrl}/rest/v1/attendance_logs`;
    
    // Simulate what the manual sync does for a member with null user_id
    const payload = {
        id: "77777777-7777-7777-7777-777777777777",
        gym_id: "f6468653-aab8-4f8b-ac79-d139313270bb", 
        member_id: "732b13fa-6d1a-4d7a-b9c1-7c93e36e8e8e", 
        user_type: "Member",
        role: "Member",
        date: "02-08-2026",
        check_in: new Date().toISOString(),
        status: "Present",
        method: "Manual"
    };

    console.log("Attempting test insert into attendance_logs...");
    try {
        const res = await fetch(url, {
            method: "POST",
            headers,
            body: JSON.stringify(payload)
        });
        const data = await res.json();
        console.log("Result:", JSON.stringify(data, null, 2));
    } catch (e) {
        console.error("Error:", e);
    }
}

testInsert();
