// @openc3/js-common/services for unit tests: the real config parser (no
// browser needed), the network services stubbed (they read location and
// open sockets)
export {
  ConfigParserError,
  ConfigParserService,
} from '../../../openc3-js-common/src/services/configParser'

export const Api = {
  get: () => Promise.resolve({ data: [] }),
  post: () => Promise.resolve({}),
}
export const axios = Api
export class Cable {}
export class OpenC3Api {}
