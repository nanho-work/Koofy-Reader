import {Content,Asset,assertRevision,requireSuperAdmin,requireValue} from './content';
/** Only the saved cover may be signed; a caller never supplies a storage path. */
export function adminCoverAsset(item:Content,expected:number,claims:{superAdmin?:unknown}):Asset {
 requireSuperAdmin(claims);assertRevision(item,expected);
 requireValue(item.kind==='book'||item.kind==='series','도서 표지만 미리 볼 수 있습니다.');
 const asset=item.assets.cover;
 requireValue(!!asset&&asset.contentType.startsWith('image/'),'등록된 대표 표지가 없습니다.');
 requireValue(asset.path.startsWith(`readerContent/${item.id}/`)||asset.path.startsWith('readerSharedCovers/'),'표지 경로를 확인해 주세요.');
 return asset;
}
