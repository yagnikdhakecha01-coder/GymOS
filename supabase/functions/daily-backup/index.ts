// =============================================
// GYMOS DAILY BACKUP — Supabase Edge Function
// =============================================
// Deploy: supabase functions deploy daily-backup
// Schedule: Set up a cron trigger in Supabase Dashboard
//           or call this endpoint daily via external cron
//
// Trigger URL: https://<project-id>.supabase.co/functions/v1/daily-backup
// Auth: Pass Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>
// =============================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

Deno.serve(async (req: Request) => {
  try {
    // Create admin client with service_role key (full access)
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    console.log('[DAILY-BACKUP] Starting full database backup...');

    // 1. Call the save_daily_backup RPC
    const { data: backupResult, error: backupError } = await supabase.rpc('save_daily_backup');

    if (backupError) {
      console.error('[DAILY-BACKUP] Backup RPC failed:', backupError.message);
      return new Response(
        JSON.stringify({ success: false, error: backupError.message }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }

    console.log('[DAILY-BACKUP] Backup saved successfully:', JSON.stringify(backupResult));

    // 2. Try Google Drive upload if configured
    let driveUrl: string | null = null;
    try {
      const { data: driveConfig } = await supabase
        .from('platform_settings')
        .select('value')
        .eq('key', 'google_drive_config')
        .maybeSingle();

      if (driveConfig?.value?.access_token) {
        const accessToken = driveConfig.value.access_token;
        const folderId = driveConfig.value.folder_id;

        // Fetch the backup data
        const backupId = backupResult?.backup_id;
        if (backupId) {
          const { data: backupRow } = await supabase
            .from('database_backups')
            .select('backup_data')
            .eq('id', backupId)
            .single();

          if (backupRow?.backup_data) {
            const jsonStr = JSON.stringify(backupRow.backup_data);
            const now = new Date();
            const fileName = `gymos_backup_${now.toISOString().split('T')[0]}_${now.getHours().toString().padStart(2, '0')}${now.getMinutes().toString().padStart(2, '0')}.json`;

            // Upload to Google Drive
            const metadata: Record<string, string> = {
              name: fileName,
              mimeType: 'application/json',
            };
            if (folderId) {
              metadata.parents = folderId;
            }

            const boundary = '===gymos_backup_boundary===';
            const body = `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(metadata)}\r\n--${boundary}\r\nContent-Type: application/json\r\n\r\n${jsonStr}\r\n--${boundary}--`;

            const driveResponse = await fetch(
              'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink',
              {
                method: 'POST',
                headers: {
                  Authorization: `Bearer ${accessToken}`,
                  'Content-Type': `multipart/related; boundary=${boundary}`,
                },
                body,
              }
            );

            if (driveResponse.ok) {
              const driveData = await driveResponse.json();
              driveUrl = driveData.webViewLink || `https://drive.google.com/file/d/${driveData.id}/view`;

              // Save drive URL to backup record
              await supabase
                .from('database_backups')
                .update({ drive_url: driveUrl })
                .eq('id', backupId);

              console.log('[DAILY-BACKUP] Uploaded to Google Drive:', driveUrl);
            } else {
              console.warn('[DAILY-BACKUP] Drive upload failed:', driveResponse.status);
            }
          }
        }
      }
    } catch (driveErr) {
      console.warn('[DAILY-BACKUP] Drive upload skipped:', driveErr);
    }

    // 3. Log to activity_logs
    try {
      await supabase.from('activity_logs').insert({
        gym_id: null,
        action: 'daily_backup',
        details: `Automatic daily backup completed. ${backupResult?.total_records ?? 0} records (${backupResult?.size_readable ?? '0 B'})${driveUrl ? ' • Uploaded to Drive' : ''}`,
        performed_by: 'System (Edge Function)',
      });
    } catch (_) {}

    return new Response(
      JSON.stringify({
        success: true,
        ...backupResult,
        drive_url: driveUrl,
        message: `Daily backup complete! ${backupResult?.total_records ?? 0} records saved.${driveUrl ? ' Uploaded to Google Drive.' : ''}`,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  } catch (err) {
    console.error('[DAILY-BACKUP] Fatal error:', err);
    return new Response(
      JSON.stringify({ success: false, error: String(err) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});
