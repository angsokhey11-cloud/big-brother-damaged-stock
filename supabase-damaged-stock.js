/* =========================================================
   BIG BROTHER — Damaged Stock Supabase Adapter V1
   Repo: big-brother-damaged-stock

   PURPOSE:
   - Read Remaining Damaged Stock
   - Read Cleared Damaged Stock
   - Read the 3 Damaged Stock clearance types

   IMPORTANT:
   - REPORTING ONLY
   - NO STOCK KEY-IN
   - NO DATABASE WRITE
   ========================================================= */

(function () {
  "use strict";

  const SUPABASE_URL =
    "https://sjfhlaclgmkwwofzstok.supabase.co";

  const SUPABASE_KEY =
    "sb_publishable_w762jR65CWwlO30fKQsYOw_6L9grx8S";

  /*
   * This is the same login session used by the
   * BIG BROTHER Dashboard.
   *
   * Because all BIG BROTHER GitHub Pages repos are under:
   * https://angsokhey11-cloud.github.io/
   *
   * they can share this localStorage session.
   */
  const SESSION_KEY =
    "BB_SUPABASE_DEV_SESSION_V1";

  let session = null;

  /* =========================================================
     SESSION
     ========================================================= */

  function readSession() {
    try {
      return JSON.parse(
        localStorage.getItem(SESSION_KEY) || "null"
      );
    } catch (_) {
      return null;
    }
  }


  function saveSession(nextSession) {
    session = nextSession || null;

    try {
      if (!nextSession) {
        localStorage.removeItem(SESSION_KEY);
        return;
      }

      if (
        !nextSession.expires_at &&
        nextSession.expires_in
      ) {
        nextSession.expires_at =
          Math.floor(Date.now() / 1000) +
          Number(nextSession.expires_in);
      }

      localStorage.setItem(
        SESSION_KEY,
        JSON.stringify(nextSession)
      );

    } catch (_) {}
  }


  async function parseResponse(response) {
    const text = await response.text();

    let data = {};

    try {
      data = text
        ? JSON.parse(text)
        : {};
    } catch (_) {
      data = {
        message: text
      };
    }

    if (!response.ok) {
      throw new Error(
        data.message ||
        data.error_description ||
        data.error ||
        "Supabase request failed (" +
        response.status +
        ")"
      );
    }

    return data;
  }


  async function refreshSession() {
    const current =
      readSession();

    if (!current?.refresh_token) {
      throw new Error(
        "Please sign in to BIG BROTHER first."
      );
    }

    const response =
      await fetch(
        SUPABASE_URL +
        "/auth/v1/token?grant_type=refresh_token",
        {
          method: "POST",

          headers: {
            apikey: SUPABASE_KEY,
            "Content-Type": "application/json"
          },

          body: JSON.stringify({
            refresh_token:
              current.refresh_token
          }),

          cache: "no-store"
        }
      );

    const next =
      await parseResponse(response);

    saveSession(next);

    return next;
  }


  async function ensureSession() {
    session =
      readSession();

    if (!session?.access_token) {
      throw new Error(
        "Please sign in to BIG BROTHER first."
      );
    }

    const now =
      Math.floor(Date.now() / 1000);

    /*
     * Refresh a little early so a report does not fail
     * while the token is about to expire.
     */
    if (
      session.expires_at &&
      Number(session.expires_at) <
        now + 30
    ) {
      await refreshSession();

      session =
        readSession();
    }

    return session;
  }


  /* =========================================================
     SUPABASE RPC
     ========================================================= */

  async function rpc(
    functionName,
    args = {}
  ) {

    await ensureSession();

    let response =
      await fetch(
        SUPABASE_URL +
        "/rest/v1/rpc/" +
        encodeURIComponent(
          functionName
        ),
        {
          method: "POST",

          headers: {
            apikey:
              SUPABASE_KEY,

            Authorization:
              "Bearer " +
              session.access_token,

            "Content-Type":
              "application/json"
          },

          body:
            JSON.stringify(
              args || {}
            ),

          cache:
            "no-store"
        }
      );

    /*
     * If token became invalid between
     * ensureSession() and the RPC request,
     * refresh once and retry.
     */
    if (
      response.status === 401
    ) {
      await refreshSession();

      session =
        readSession();

      response =
        await fetch(
          SUPABASE_URL +
          "/rest/v1/rpc/" +
          encodeURIComponent(
            functionName
          ),
          {
            method: "POST",

            headers: {
              apikey:
                SUPABASE_KEY,

              Authorization:
                "Bearer " +
                session.access_token,

              "Content-Type":
                "application/json"
            },

            body:
              JSON.stringify(
                args || {}
              ),

            cache:
              "no-store"
          }
        );
    }

    return parseResponse(
      response
    );
  }


  /* =========================================================
     DAMAGED STOCK REPORT
     ========================================================= */

  async function getDamageReport() {

    /*
     * Returns:
     *
     * totals:
     * - productCount
     * - damagedQty
     * - damagedValue
     *
     * rows:
     * - productCode
     * - productName
     * - category
     * - unit
     * - damagedQty
     * - averageCost
     * - damagedValue
     *
     * recent:
     * - recent damage transactions
     */
    return rpc(
      "bb_stock_damage_report"
    );
  }


  /* =========================================================
     CLEARED DAMAGED STOCK
     ========================================================= */

  async function getClearedDamage(
    limit = 1000
  ) {

    let safeLimit =
      Number(limit) || 1000;

    safeLimit =
      Math.max(
        1,
        Math.min(
          safeLimit,
          2000
        )
      );

    /*
     * Returns:
     *
     * rows:
     * - activityDate
     * - clearanceType
     * - clearanceTypeLabel
     * - productCode
     * - productName
     * - qty
     * - unit
     * - unitCost
     * - lineValue
     * - location
     * - controller
     * - reference
     * - note
     * - movementId
     *
     * totals:
     * - lineCount
     * - clearedQty
     * - clearedValue
     */
    return rpc(
      "bb_stock_damage_cleared",
      {
        p_limit:
          safeLimit
      }
    );
  }


  /* =========================================================
     CLEARANCE TYPES
     ========================================================= */

  async function getClearanceTypes() {

    /*
     * Current categories:
     *
     * 1. Deduct as Cost
     * 2. Client Buy Back
     * 3. Exchange for Good products
     */
    return rpc(
      "bb_stock_damage_clearance_types"
    );
  }


  /* =========================================================
     LOAD EVERYTHING
     ========================================================= */

  async function loadAll() {

    const [
      remaining,
      cleared,
      clearanceTypes
    ] =
      await Promise.all([
        getDamageReport(),
        getClearedDamage(1000),
        getClearanceTypes()
      ]);

    return {
      remaining:
        remaining || {},

      cleared:
        cleared || {},

      clearanceTypes:
        clearanceTypes || {}
    };
  }


  /* =========================================================
     HELPERS
     ========================================================= */

  function money(value) {
    const n =
      Number(value) || 0;

    return (
      "$" +
      n.toLocaleString(
        undefined,
        {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2
        }
      )
    );
  }


  function qty(value) {
    const n =
      Number(value) || 0;

    return n.toLocaleString(
      undefined,
      {
        maximumFractionDigits: 3
      }
    );
  }


  function clean(value) {
    return String(
      value == null
        ? ""
        : value
    ).trim();
  }


  function escapeHtml(value) {
    return clean(value)
      .replace(
        /&/g,
        "&amp;"
      )
      .replace(
        /</g,
        "&lt;"
      )
      .replace(
        />/g,
        "&gt;"
      )
      .replace(
        /"/g,
        "&quot;"
      )
      .replace(
        /'/g,
        "&#39;"
      );
  }


  /* =========================================================
     PUBLIC API
     ========================================================= */

  window.BBDamagedStock = {

    version:
      "DAMAGED-STOCK-ADAPTER-V1",

    rpc,

    ensureSession,

    refreshSession,

    getDamageReport,

    getClearedDamage,

    getClearanceTypes,

    loadAll,

    money,

    qty,

    clean,

    escapeHtml
  };

})();
