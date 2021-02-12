jQuery(function($){

    /*$('body.home .entry-content').each(function(){
        if($(this).height() > 300) {
            $(this).closest('article').addClass('o-excerpt');
            $('<div/>', {
                class: 'o-more-btn',
                html: '<span>Afficher l\'article complet ⟱</span>'
            }).insertAfter($(this));
        }
    });*/

    /*$('article').on('click', '.o-more-btn', function(){
        window.location.href = $(this).closest('article').find('h2.entry-title a').attr('href');
        //$(this).closest('article').removeClass('o-excerpt').end().remove();
    });*/

    $('a[href*=".jpg"], a[href*=".jpeg"], a[href*=".png"], a[href*=".gif"]').each(function(){
        if ($(this).parents('.gallery').length == 0) {
            $(this).magnificPopup({
                type:'image',
                closeOnContentClick: true
            });
        }
    });
    $('.gallery').each(function() {
        $(this).magnificPopup({
            delegate: 'a',
            type: 'image',
            gallery: { enabled: true }
        });
    });

});