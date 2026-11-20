export interface AuthenticatedUser {
  id: string;
  email: string | null;
  accessToken: string;
}
