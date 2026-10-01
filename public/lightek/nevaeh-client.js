(() => {
  class NevaehClient {
    constructor(options = {}) {
      this.baseUrl =
        options.baseUrl ||
        "/api/nevaeh"

      this.subscriptions =
        new Map()

      this.bootstrapState =
        null
    }

    async bootstrap(options = {}) {
      const response =
        await fetch(
          `${this.baseUrl}/bootstrap`,
          {
            method: "GET",
            credentials: "same-origin",
            headers: {
              Accept:
                "application/json"
            },
            signal:
              options.signal
          }
        )

      const data =
        await this.parseResponse(
          response
        )

      this.bootstrapState = data


      this.csrfToken =

        data.csrf_token ||

        null
      this.emit(
        "nevaeh.bootstrap",
        data
      )

      return data
    }

    async execute(request) {
      if (
        !request ||
        typeof request !== "object"
      ) {
        throw new TypeError(
          "nevaeh.execute requires a request object"
        )
      }

      if (!request.capability) {
        throw new TypeError(
          "nevaeh.execute requires capability"
        )
      }

      const endpoint =
        request.capability === "payments.quote"
          ? `${this.baseUrl}/payment_quote`
          : `${this.baseUrl}/execute`

      const body =
        request.capability === "payments.quote"
          ? request.payload
          : request

      const response =
        await fetch(
          endpoint,
          {
            method: "POST",
            credentials:
              "same-origin",
            headers: {
              Accept:
                "application/json",
              "Content-Type":
                "application/json",
              ...this.csrfHeaders()
            },
            body:
              JSON.stringify(
                body
              )
          }
        )

      const data =
        await this.parseResponse(
          response
        )

      this.emit(
        "nevaeh.execute",
        {
          request,
          response: data
        }
      )

      return data
    }

    subscribe(options) {
      if (
        !options ||
        !options.subject
      ) {
        throw new TypeError(
          "nevaeh.subscribe requires subject"
        )
      }

      const subject =
        options.subject

      const key =
        String(subject)

      const subscription = {
        subject,
        unsubscribe: () => {
          this.subscriptions
            .delete(key)

          this.emit(
            "nevaeh.unsubscribe",
            { subject }
          )
        }
      }

      this.subscriptions.set(
        key,
        subscription
      )

      this.emit(
        "nevaeh.subscribe",
        { subject }
      )

      return subscription
    }

    csrfHeaders() {
      const token =
        this.csrfToken ||
          document
            .querySelector(
              'meta[name="csrf-token"]'
            )
            ?.getAttribute(
              "content"
            )

      return token
        ? {
            "X-CSRF-Token":
              token
          }
        : {}
    }

    async parseResponse(response) {
      const data =
        await response
          .json()
          .catch(() => ({}))

      if (!response.ok) {
        const error =
          new Error(
            data.error ||
            data.message ||
            `Nevaeh request failed (${response.status})`
          )

        error.status =
          response.status

        error.data =
          data

        throw error
      }

      return data
    }

    emit(name, detail) {
      window.dispatchEvent(
        new CustomEvent(
          name,
          { detail }
        )
      )
    }
  }

  window.NevaehClient =
    NevaehClient

  window.nevaeh =
    new NevaehClient()
})()
