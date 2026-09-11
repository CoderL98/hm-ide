export interface HmSshResult {
  ok: boolean;
  code: string;
  message: string;
  arch?: string;
}

export const available: () => HmSshResult;
export const detectRemoteArch: (
  host: string, port: number, user: string,
  authMode: string, privateKeyPath: string, password: string
) => HmSshResult;
export const uploadAgent: (
  localBinary: string, host: string, port: number, user: string,
  authMode: string, privateKeyPath: string, password: string, agentPort: number
) => HmSshResult;
export const installAndStart: (
  host: string, port: number, user: string,
  authMode: string, privateKeyPath: string, password: string,
  agentPort: number, token: string
) => HmSshResult;
export const localForward: (
  host: string, port: number, user: string,
  authMode: string, privateKeyPath: string, password: string, agentPort: number
) => HmSshResult;
export const replaceAndRestart: (
  localBinary: string, host: string, port: number, user: string,
  authMode: string, privateKeyPath: string, password: string, agentPort: number
) => HmSshResult;
export const deployAll: (
  localBinary: string, host: string, port: number, user: string,
  authMode: string, privateKeyPath: string, password: string,
  agentPort: number, token: string
) => HmSshResult;
export const hostHelperHint: () => HmSshResult;
