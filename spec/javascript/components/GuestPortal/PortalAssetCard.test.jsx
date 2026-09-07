import React from 'react';
import { render, screen } from '@testing-library/react';
import i18n from 'i18next';
import en from '../../../../app/javascript/i18n/locales/en.json';
import PortalAssetCard from '../../../../app/javascript/components/GuestPortal/PortalAssetCard';

i18n.addResourceBundle('en', 'translation', en, true, true);

const asset = (overrides = {}) => ({
    id: 'a1',
    title: 'Hero shot',
    content_type: 'image/jpeg',
    byte_size: 2048,
    preview_url: '/s/portal/tok/assets/a1/preview',
    downloadable: true,
    download_url: '/s/portal/tok/assets/a1/download',
    ...overrides,
});

const renderCard = (overrides = {}) => render(
    <PortalAssetCard asset={asset(overrides)} accent="#1f6feb" />,
);

describe('PortalAssetCard', () => {
    it('links the download button at the signed portal path', () => {
        renderCard();

        expect(screen.getByTestId('portal-download-button'))
            .toHaveAttribute('href', '/s/portal/tok/assets/a1/download');
    });

    describe('a view-only asset', () => {
        const viewOnly = { downloadable: false, download_url: null };

        it('says so rather than silently omitting the control', () => {
            renderCard(viewOnly);

            expect(screen.getByTestId('portal-view-only')).toBeInTheDocument();
        });

        it('offers no usable download link', () => {
            renderCard(viewOnly);

            // The server would refuse anyway; rendering a link the partner
            // cannot use turns a clear rule into an apparent bug.
            expect(screen.queryByTestId('portal-download-button')).not.toBeInTheDocument();
            expect(screen.getByRole('button', { name: /download/i })).toBeDisabled();
        });
    });

    it('previews an image inline', () => {
        renderCard();

        expect(screen.getByRole('img', { name: 'Hero shot' }))
            .toHaveAttribute('src', '/s/portal/tok/assets/a1/preview');
        expect(screen.queryByTestId('portal-asset-placeholder')).not.toBeInTheDocument();
    });

    it('shows a placeholder for a non-image rather than a broken image', () => {
        renderCard({ content_type: 'application/pdf' });

        // The preview endpoint streams original bytes, so an <img> pointed at
        // a PDF renders as a broken-image icon.
        expect(screen.getByTestId('portal-asset-placeholder')).toBeInTheDocument();
        expect(screen.queryByRole('img', { name: 'Hero shot' })).not.toBeInTheDocument();
    });

    it('shows a placeholder when the content type is unknown', () => {
        renderCard({ content_type: null });

        expect(screen.getByTestId('portal-asset-placeholder')).toBeInTheDocument();
    });

    describe('file size', () => {
        it('renders bytes in human units', () => {
            renderCard({ byte_size: 2048 });

            expect(screen.getByText('2.0 KB')).toBeInTheDocument();
        });

        it('leaves small sizes in bytes without a decimal', () => {
            renderCard({ byte_size: 512 });

            expect(screen.getByText('512 B')).toBeInTheDocument();
        });

        it('scales past megabytes', () => {
            renderCard({ byte_size: 5 * 1024 * 1024 });

            expect(screen.getByText('5.0 MB')).toBeInTheDocument();
        });

        it('omits the chip when the size is unknown', () => {
            renderCard({ byte_size: null });

            // An unknown size must not render as "0 B", which reads as a
            // corrupt file rather than missing metadata.
            expect(screen.queryByText(/\d+(\.\d+)? (B|KB|MB|GB)/)).not.toBeInTheDocument();
        });
    });
});
